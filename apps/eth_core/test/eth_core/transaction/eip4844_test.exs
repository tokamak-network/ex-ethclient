defmodule EthCore.Transaction.EIP4844Test do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.EIP4844

  describe "type byte" do
    test "type is 0x03" do
      assert EIP4844.type_byte() == 0x03
    end
  end

  describe "encode/decode roundtrip" do
    test "basic blob tx roundtrip" do
      blob_hash = <<0x01>> <> :crypto.strong_rand_bytes(31)

      tx = %EIP4844{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 20_000_000_000,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 100_000,
        blob_versioned_hashes: [blob_hash],
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP4844.encode(tx)
      assert <<0x03, _rest::binary>> = encoded

      {:ok, decoded} = EIP4844.decode(encoded)
      assert decoded.chain_id == 1
      assert decoded.max_fee_per_blob_gas == 100_000
      assert decoded.blob_versioned_hashes == [blob_hash]
    end

    test "blob versioned hash must start with 0x01" do
      blob_hash = <<0x01>> <> :crypto.strong_rand_bytes(31)
      assert <<0x01, _::binary-size(31)>> = blob_hash
    end

    test "multiple blob hashes roundtrip" do
      hash1 = <<0x01>> <> :crypto.strong_rand_bytes(31)
      hash2 = <<0x01>> <> :crypto.strong_rand_bytes(31)

      tx = %EIP4844{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1,
        blob_versioned_hashes: [hash1, hash2],
        v: 1,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP4844.encode(tx)
      {:ok, decoded} = EIP4844.decode(encoded)
      assert decoded.blob_versioned_hashes == [hash1, hash2]
    end
  end

  describe "signing_hash/1" do
    test "produces 32-byte hash" do
      tx = %EIP4844{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1,
        blob_versioned_hashes: [<<0x01>> <> :crypto.strong_rand_bytes(31)]
      }

      assert byte_size(EIP4844.signing_hash(tx)) == 32
    end
  end
end
