defmodule EthCore.Transaction.EIP2930Test do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.EIP2930

  describe "type byte" do
    test "type is 0x01" do
      assert EIP2930.type_byte() == 0x01
    end
  end

  describe "encode/decode roundtrip" do
    test "empty access list roundtrip" do
      tx = %EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower),
        value: 1_000_000,
        data: "",
        access_list: [],
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP2930.encode(tx)
      # Typed tx envelope: 0x01 || rlp(...)
      assert <<0x01, _rest::binary>> = encoded

      {:ok, decoded} = EIP2930.decode(encoded)
      assert decoded.chain_id == tx.chain_id
      assert decoded.nonce == tx.nonce
      assert decoded.gas_price == tx.gas_price
      assert decoded.gas_limit == tx.gas_limit
      assert decoded.to == tx.to
      assert decoded.value == tx.value
      assert decoded.access_list == []
    end

    test "access list with entries roundtrip" do
      storage_key = :crypto.strong_rand_bytes(32)
      address = :crypto.strong_rand_bytes(20)

      tx = %EIP2930{
        chain_id: 1,
        nonce: 5,
        gas_price: 10_000_000_000,
        gas_limit: 50_000,
        to: Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower),
        value: 0,
        data: <<0x60, 0x00>>,
        access_list: [{address, [storage_key]}],
        v: 1,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP2930.encode(tx)
      {:ok, decoded} = EIP2930.decode(encoded)

      assert decoded.access_list == [{address, [storage_key]}]
      assert decoded.chain_id == 1
      assert decoded.nonce == 5
    end
  end

  describe "signing_hash/1" do
    test "produces 32-byte hash" do
      tx = %EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: []
      }

      hash = EIP2930.signing_hash(tx)
      assert byte_size(hash) == 32
    end
  end
end
