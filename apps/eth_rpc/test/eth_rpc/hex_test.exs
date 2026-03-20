defmodule EthRpc.HexTest do
  use ExUnit.Case, async: true

  alias EthRpc.Hex

  describe "encode_quantity/1" do
    test "encodes 0" do
      assert Hex.encode_quantity(0) == "0x0"
    end

    test "encodes positive integers without leading zeros" do
      assert Hex.encode_quantity(1) == "0x1"
      assert Hex.encode_quantity(16) == "0x10"
      assert Hex.encode_quantity(255) == "0xff"
      assert Hex.encode_quantity(256) == "0x100"
    end

    test "encodes large integers" do
      assert Hex.encode_quantity(1_000_000) == "0xf4240"
      assert Hex.encode_quantity(21_000) == "0x5208"
    end
  end

  describe "encode_data/1" do
    test "encodes empty binary" do
      assert Hex.encode_data(<<>>) == "0x"
    end

    test "encodes binary data with even hex digits" do
      assert Hex.encode_data(<<1, 2, 3>>) == "0x010203"
      assert Hex.encode_data(<<0, 0, 0>>) == "0x000000"
    end

    test "encodes 32-byte hash" do
      hash = :crypto.strong_rand_bytes(32)
      result = Hex.encode_data(hash)
      assert String.starts_with?(result, "0x")
      # 32 bytes = 64 hex chars + "0x" prefix
      assert byte_size(result) == 66
    end
  end

  describe "decode_quantity/1" do
    test "decodes 0x0" do
      assert Hex.decode_quantity("0x0") == {:ok, 0}
    end

    test "decodes hex quantities" do
      assert Hex.decode_quantity("0x1") == {:ok, 1}
      assert Hex.decode_quantity("0xff") == {:ok, 255}
      assert Hex.decode_quantity("0xFF") == {:ok, 255}
      assert Hex.decode_quantity("0x5208") == {:ok, 21_000}
    end

    test "rejects invalid input" do
      assert Hex.decode_quantity("0x") == {:error, :invalid_hex}
      assert Hex.decode_quantity("ff") == {:error, :invalid_hex}
      assert Hex.decode_quantity("invalid") == {:error, :invalid_hex}
      assert Hex.decode_quantity("") == {:error, :invalid_hex}
    end
  end

  describe "decode_data/1" do
    test "decodes empty data" do
      assert Hex.decode_data("0x") == {:ok, <<>>}
    end

    test "decodes hex data" do
      assert Hex.decode_data("0x010203") == {:ok, <<1, 2, 3>>}
      assert Hex.decode_data("0x000000") == {:ok, <<0, 0, 0>>}
    end

    test "decodes odd-length hex by padding" do
      assert Hex.decode_data("0x1") == {:ok, <<1>>}
    end

    test "rejects invalid input" do
      assert Hex.decode_data("010203") == {:error, :invalid_hex}
      assert Hex.decode_data("0xGG") == {:error, :invalid_hex}
    end
  end
end
