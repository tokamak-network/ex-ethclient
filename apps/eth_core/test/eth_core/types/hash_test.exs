defmodule EthCore.Types.HashTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Hash

  @empty_hash_hex "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
  @empty_hash_bytes Base.decode16!(
                      "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
                      case: :lower
                    )

  describe "new/1" do
    test "accepts 32-byte binary" do
      assert {:ok, hash} = Hash.new(@empty_hash_bytes)
      assert hash.bytes == @empty_hash_bytes
    end

    test "rejects wrong size binary" do
      assert {:error, _} = Hash.new(<<0::8*31>>)
      assert {:error, _} = Hash.new(<<0::8*33>>)
    end
  end

  describe "from_hex/1" do
    test "parses 0x-prefixed hex" do
      assert {:ok, hash} = Hash.from_hex(@empty_hash_hex)
      assert hash.bytes == @empty_hash_bytes
    end

    test "parses without 0x prefix" do
      assert {:ok, hash} =
               Hash.from_hex("c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")

      assert hash.bytes == @empty_hash_bytes
    end

    test "rejects invalid hex" do
      assert {:error, _} = Hash.from_hex("0xZZZZ")
    end
  end

  describe "to_hex/1" do
    test "returns 0x-prefixed lowercase hex" do
      {:ok, hash} = Hash.new(@empty_hash_bytes)
      assert Hash.to_hex(hash) == @empty_hash_hex
    end
  end

  describe "zero/0" do
    test "returns 32-byte zero hash" do
      hash = Hash.zero()
      assert hash.bytes == <<0::256>>
    end
  end

  describe "compute/1" do
    test "empty string produces known empty hash" do
      hash = Hash.compute("")
      assert hash.bytes == @empty_hash_bytes
    end

    test "result is always 32 bytes" do
      hash = Hash.compute("hello world")
      assert byte_size(hash.bytes) == 32
    end
  end
end
