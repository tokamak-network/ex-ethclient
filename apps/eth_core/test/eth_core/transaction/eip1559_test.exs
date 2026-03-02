defmodule EthCore.Transaction.EIP1559Test do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.EIP1559

  describe "type byte" do
    test "type is 0x02" do
      assert EIP1559.type_byte() == 0x02
    end
  end

  describe "encode/decode roundtrip" do
    test "basic EIP-1559 tx roundtrip" do
      tx = %EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower),
        value: 1_000_000,
        data: "",
        access_list: [],
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP1559.encode(tx)
      assert <<0x02, _rest::binary>> = encoded

      {:ok, decoded} = EIP1559.decode(encoded)
      assert decoded.chain_id == 1
      assert decoded.nonce == 0
      assert decoded.max_priority_fee_per_gas == 1_000_000_000
      assert decoded.max_fee_per_gas == 20_000_000_000
      assert decoded.gas_limit == 21_000
      assert decoded.value == 1_000_000
    end

    test "contract creation with nil to" do
      tx = %EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 53_000,
        to: nil,
        value: 0,
        data: <<0x60, 0x00, 0x60, 0x00>>,
        access_list: [],
        v: 1,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP1559.encode(tx)
      {:ok, decoded} = EIP1559.decode(encoded)
      assert decoded.to == nil
      assert decoded.data == <<0x60, 0x00, 0x60, 0x00>>
    end

    test "with access list" do
      address = :crypto.strong_rand_bytes(20)
      key1 = :crypto.strong_rand_bytes(32)
      key2 = :crypto.strong_rand_bytes(32)

      tx = %EIP1559{
        chain_id: 1,
        nonce: 10,
        max_priority_fee_per_gas: 2_000_000_000,
        max_fee_per_gas: 50_000_000_000,
        gas_limit: 100_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: :crypto.strong_rand_bytes(64),
        access_list: [{address, [key1, key2]}],
        v: 0,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = EIP1559.encode(tx)
      {:ok, decoded} = EIP1559.decode(encoded)
      assert decoded.access_list == [{address, [key1, key2]}]
    end
  end

  describe "signing_hash/1" do
    test "produces 32-byte hash" do
      tx = %EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: :crypto.strong_rand_bytes(20),
        value: 0,
        data: "",
        access_list: []
      }

      assert byte_size(EIP1559.signing_hash(tx)) == 32
    end
  end
end
