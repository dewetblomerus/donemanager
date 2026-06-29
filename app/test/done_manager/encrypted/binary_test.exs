defmodule DoneManager.Encrypted.BinaryTest do
  use ExUnit.Case, async: false

  alias DoneManager.Encrypted.Binary

  @config_app :done_manager
  @config_key DoneManager.Encrypted
  @empty_aad ""

  setup do
    original = Application.fetch_env!(@config_app, @config_key)

    on_exit(fn ->
      Application.put_env(@config_app, @config_key, original)
    end)

    :ok
  end

  test "round-trips a value through dump/load" do
    {:ok, blob} = Binary.dump("u-secret-key")
    assert {:ok, "u-secret-key"} = Binary.load(blob)
  end

  test "ciphertext is not the plaintext and carries the primary key id" do
    plaintext = "u-secret-key"
    {:ok, <<key_id::8, _rest::binary>> = blob} = Binary.dump(plaintext)

    assert key_id == 1
    refute blob =~ plaintext
  end

  test "nil passes through" do
    assert {:ok, nil} = Binary.dump(nil)
    assert {:ok, nil} = Binary.load(nil)
  end

  test "cast treats empty string as nil" do
    assert {:ok, nil} = Binary.cast("")
    assert {:ok, "x"} = Binary.cast("x")
  end

  test "tampered ciphertext fails to decrypt" do
    {:ok, <<head::binary-29, first, rest::binary>>} = Binary.dump("u-secret-key")
    tampered = <<head::binary, Bitwise.bxor(first, 1), rest::binary>>

    assert :error = Binary.load(tampered)
  end

  test "ciphertext encrypted without the field context does not decrypt" do
    key = configured_key(1)
    iv = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, "u-secret-key", @empty_aad, true)

    blob = <<1::8, iv::binary-12, tag::binary-16, ciphertext::binary>>

    assert :error = Binary.load(blob)
  end

  test "validates key length" do
    Application.put_env(@config_app, @config_key, keys: %{1 => "too-short"}, primary: 1)

    assert_raise ArgumentError, ~r/32-byte binary/, fn ->
      Binary.validate_config!()
    end
  end

  test "validates primary key is configured" do
    Application.put_env(@config_app, @config_key, keys: %{1 => configured_key(1)}, primary: 2)

    assert_raise ArgumentError, ~r/primary to reference a configured key/, fn ->
      Binary.validate_config!()
    end
  end

  test "returns error when ciphertext references an unknown key id" do
    {:ok, <<_key_id::8, rest::binary>>} = Binary.dump("u-secret-key")

    assert :error = Binary.load(<<2::8, rest::binary>>)
  end

  defp configured_key(key_id) do
    @config_app
    |> Application.fetch_env!(@config_key)
    |> Keyword.fetch!(:keys)
    |> Map.fetch!(key_id)
  end
end
