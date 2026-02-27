defmodule EthCore.Types.HashTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Hash

  describe "new/1" do
    test "accepts 32-byte binary" do
      bytes = :crypto.strong_rand_bytes(32)
      assert {:ok, ^bytes} = Hash.new(bytes)
    end

    test "rejects wrong size" do
      assert {:error, :invalid_hash} = Hash.new(<<1, 2, 3>>)
      assert {:error, :invalid_hash} = Hash.new(:crypto.strong_rand_bytes(31))
      assert {:error, :invalid_hash} = Hash.new(:crypto.strong_rand_bytes(33))
    end
  end

  describe "from_hex/1" do
    test "parses 0x-prefixed hex" do
      hex = "0x" <> String.duplicate("ab", 32)
      {:ok, hash} = Hash.from_hex(hex)
      assert byte_size(hash) == 32
    end

    test "parses plain hex" do
      hex = String.duplicate("cd", 32)
      {:ok, hash} = Hash.from_hex(hex)
      assert byte_size(hash) == 32
    end

    test "rejects invalid hex" do
      assert {:error, :invalid_hex} = Hash.from_hex("0xgg" <> String.duplicate("00", 30))
      assert {:error, :invalid_hex} = Hash.from_hex("too_short")
    end
  end

  describe "to_hex/1" do
    test "round-trips with from_hex" do
      original = "0x" <> String.duplicate("ab", 32)
      {:ok, hash} = Hash.from_hex(original)
      assert Hash.to_hex(hash) == original
    end
  end

  describe "zero/0" do
    test "is 32 zero bytes" do
      assert Hash.zero() == <<0::256>>
    end
  end
end
