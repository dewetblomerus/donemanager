defmodule DoneManager.Encrypted.Binary do
  @moduledoc """
  An `Ecto.Type` that encrypts a string at rest with AES-256-GCM (OTP `:crypto`,
  no third-party deps).

  Stored layout: `<<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>`.
  The leading `key_id` lets multiple keys coexist, so key rotation is a config
  change plus a re-encryption pass — no maintenance window. Configure with:

      config :done_manager, DoneManager.Encrypted,
        keys: %{1 => <<32 bytes>>},
        primary: 1
  """

  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(""), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(plaintext) when is_binary(plaintext) do
    key_id = primary_id()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(key_id), iv, plaintext, "", true)

    {:ok, <<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>}
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(<<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(key_id), iv, ciphertext, "", tag, false) do
      :error -> :error
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
    end
  end

  def load(_), do: :error

  defp config, do: Application.fetch_env!(:done_manager, DoneManager.Encrypted)

  defp primary_id, do: Keyword.fetch!(config(), :primary)

  defp key(key_id) do
    config()
    |> Keyword.fetch!(:keys)
    |> Map.fetch!(key_id)
  end
end
