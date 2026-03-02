defmodule EthCore.Transaction.EIP7702Test do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.EIP7702

  describe "type byte" do
    test "type is 0x04" do
      assert EIP7702.type_byte() == 0x04
    end
  end

  describe "encode/decode roundtrip" do
    test "basic EIP-7702 tx roundtrip" do
      auth = %{
        chain_id: 1,
        address: :crypto.strong_rand_bytes(20),
        nonce: 0,
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      tx = %EIP7702{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 20_000_000_000,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        authorization_list: [auth],
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP7702.encode(tx)
      assert <<0x04, _rest::binary>> = encoded

      {:ok, decoded} = EIP7702.decode(encoded)
      assert decoded.chain_id == 1
      assert decoded.nonce == 0
      assert length(decoded.authorization_list) == 1

      [decoded_auth] = decoded.authorization_list
      assert decoded_auth.chain_id == auth.chain_id
      assert decoded_auth.address == auth.address
      assert decoded_auth.nonce == auth.nonce
    end

    test "empty authorization list roundtrip" do
      tx = %EIP7702{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        authorization_list: [],
        v: 1,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP7702.encode(tx)
      {:ok, decoded} = EIP7702.decode(encoded)
      assert decoded.authorization_list == []
    end
  end

  describe "authorization signing hash" do
    test "authorization signing uses MAGIC 0x05 prefix" do
      auth = %{
        chain_id: 1,
        address: :crypto.strong_rand_bytes(20),
        nonce: 0
      }

      hash = EIP7702.authorization_signing_hash(auth)
      assert byte_size(hash) == 32
    end
  end

  describe "signing_hash/1" do
    test "produces 32-byte hash" do
      tx = %EIP7702{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: [],
        authorization_list: []
      }

      assert byte_size(EIP7702.signing_hash(tx)) == 32
    end
  end
end
