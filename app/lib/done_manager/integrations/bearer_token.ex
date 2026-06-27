defmodule DoneManager.Integrations.BearerToken do
  @moduledoc """
  An integration credential for a household. Authenticates non-browser clients
  (the NFC scan endpoint first) and optionally acts on behalf of a `user`.

  The full token is shown once at creation and never stored; only a lookup
  `prefix` and the `token_hash` are persisted. See architecture/database.md.
  """

  use DoneManager.Schema
  import Ecto.Changeset

  alias DoneManager.Accounts.User
  alias DoneManager.Households.Household

  schema "integration_bearer_tokens" do
    field :label, :string
    field :prefix, :string
    field :token_hash, :string
    field :source, :string
    field :revoked_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec

    belongs_to :household, Household
    belongs_to :user, User
    belongs_to :created_by_user, User

    timestamps()
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:label, :prefix, :token_hash, :source, :revoked_at, :last_used_at])
    |> validate_required([:prefix, :token_hash])
    |> unique_constraint(:prefix)
  end
end
