defmodule DoneManager.Integrations do
  @moduledoc """
  Integration bearer tokens: the credentials non-browser clients (the NFC scan
  endpoint) authenticate with.

  Only a household owner can mint a token. The plaintext token is returned once
  from `create_token/2` and never stored — only its `prefix` and `token_hash`.
  `authenticate/1` reverses that: extract the prefix, load the non-revoked row,
  then constant-time compare the hash.
  """

  import Ecto.Query, warn: false

  alias DoneManager.Accounts.Scope
  alias DoneManager.Accounts.User
  alias DoneManager.Households
  alias DoneManager.Households.Household
  alias DoneManager.Integrations.BearerToken
  alias DoneManager.Repo

  @prefix_bytes 6
  @secret_bytes 24

  @doc "Tokens for the scope's current household, newest first."
  def list_tokens(%Scope{household: %Household{id: household_id}}) do
    from(t in BearerToken,
      where: t.household_id == ^household_id,
      order_by: [desc: t.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Owner-only: mints a token for the scope's current household. Returns
  `{:ok, token, plaintext}` — `plaintext` is shown once and cannot be recovered.
  """
  def create_token(%Scope{user: %User{} = user} = scope, attrs \\ %{}) do
    if Households.owner?(scope) do
      prefix = random(@prefix_bytes)
      secret = random(@secret_bytes)
      plaintext = prefix <> "." <> secret

      %BearerToken{
        household_id: scope.household.id,
        user_id: user.id,
        created_by_user_id: user.id,
        source: Map.get(attrs, :source, "nfc_tasks")
      }
      |> BearerToken.changeset(%{
        label: Map.get(attrs, :label),
        prefix: prefix,
        token_hash: hash(plaintext)
      })
      |> Repo.insert()
      |> case do
        {:ok, token} -> {:ok, token, plaintext}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Resolves a plaintext bearer token to its non-revoked row with `household` and
  `user` preloaded, or `:error`. The household is the scan's tenant boundary.
  """
  def authenticate(plaintext) when is_binary(plaintext) do
    with [prefix, _secret] <- String.split(plaintext, ".", parts: 2),
         %BearerToken{} = token <- Repo.one(non_revoked_query(prefix)),
         true <- Plug.Crypto.secure_compare(token.token_hash, hash(plaintext)) do
      {:ok, Repo.preload(token, [:household, :user])}
    else
      _ -> :error
    end
  end

  def authenticate(_), do: :error

  defp non_revoked_query(prefix) do
    from t in BearerToken, where: t.prefix == ^prefix and is_nil(t.revoked_at)
  end

  defp random(bytes),
    do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp hash(plaintext), do: :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
end
