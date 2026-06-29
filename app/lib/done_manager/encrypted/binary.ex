defmodule DoneManager.Encrypted.Binary do
  @moduledoc """
  An `Ecto.Type` that encrypts a string at rest with AES-256-GCM (OTP `:crypto`,
  no third-party deps).

  Stored layout: `<<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>`.
  Ciphertexts are authenticated against this field's storage context, so blobs
  copied from another encrypted field will not decrypt here.
  The leading `key_id` lets multiple keys coexist, so key rotation is a config
  change plus a re-encryption pass — no maintenance window. Configure with:

      config :done_manager, DoneManager.Encrypted,
        keys: %{1 => <<32 bytes>>},
        primary: 1
  """

  use Ecto.Type

  @aad "DoneManager.Accounts.User:pushover_user_key"

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
    %{keys: keys, primary: key_id} = validated_config()
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        Map.fetch!(keys, key_id),
        iv,
        plaintext,
        @aad,
        true
      )

    {:ok, <<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>}
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(<<key_id::8, iv::binary-12, tag::binary-16, ciphertext::binary>>) do
    %{keys: keys} = validated_config()

    with {:ok, key} <- Map.fetch(keys, key_id) do
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false)
    end
    |> case do
      :error -> :error
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
    end
  end

  def load(_), do: :error

  def validate_config!, do: validated_config()

  defp validated_config do
    config = Application.fetch_env!(:done_manager, DoneManager.Encrypted)
    keys = Keyword.fetch!(config, :keys)
    primary = Keyword.fetch!(config, :primary)

    unless is_map(keys) do
      raise ArgumentError,
            "expected DoneManager.Encrypted :keys to be a map of key id to 32-byte key"
    end

    unless is_integer(primary) and primary in 0..255 do
      raise ArgumentError,
            "expected DoneManager.Encrypted :primary to be an integer from 0 to 255"
    end

    unless Map.has_key?(keys, primary) do
      raise ArgumentError, "expected DoneManager.Encrypted :primary to reference a configured key"
    end

    Enum.each(keys, fn
      {id, key}
      when is_integer(id) and id in 0..255 and is_binary(key) and byte_size(key) == 32 ->
        :ok

      {id, key} ->
        raise ArgumentError,
              "invalid DoneManager.Encrypted key #{inspect(id)}: expected id 0..255 and a 32-byte binary, got #{inspect(key)}"
    end)

    %{keys: keys, primary: primary}
  end
end
