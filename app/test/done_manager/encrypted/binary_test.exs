defmodule DoneManager.Encrypted.BinaryTest do
  use ExUnit.Case, async: true

  alias DoneManager.Encrypted.Binary

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
end
