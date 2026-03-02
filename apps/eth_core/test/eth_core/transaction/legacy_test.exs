defmodule EthCore.Transaction.LegacyTest do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.Legacy

  # From ethereum/tests TransactionTests/ttValue/TransactionWithHighValue.json
  # nonce=0, gasPrice=1, gasLimit=21000, to=0x095e..., value=2^256-1
  # sender=0x8411b12666f68ef74cace3615c9d5a377729d03f
  @simple_tx_hex "f87f800182520894095e7baea6a6c7c4c2dfeb977efac326af552d87a0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff801ba048b55bfa915ac795c431978d8a6a992b628d557da5ff759b307d495a36649353a01fffd310ac743f371de3b9f7f9cb56c0b28ad43601b4ab949f53faa07bd2c804"
  # sender for @simple_tx_hex: 0x8411b12666f68ef74cace3615c9d5a377729d03f

  describe "decode/1" do
    test "decodes a signed legacy transaction" do
      raw = Base.decode16!(@simple_tx_hex, case: :lower)
      assert {:ok, tx} = Legacy.decode(raw)

      assert tx.nonce == 0
      assert tx.gas_price == 1
      assert tx.gas_limit == 21_000
      assert byte_size(tx.to) == 20
      assert tx.value == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      assert tx.data == ""
      assert tx.v != nil
      assert tx.r != nil
      assert tx.s != nil
    end

    test "decodes to address correctly" do
      raw = Base.decode16!(@simple_tx_hex, case: :lower)
      {:ok, tx} = Legacy.decode(raw)
      assert tx.to == Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower)
    end

    test "contract creation has nil to" do
      # Build a contract creation tx (to=nil)
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 53_000,
        to: nil,
        value: 0,
        data: <<0x60, 0x00>>,
        v: 27,
        r: :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
        s: :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
      }

      encoded = Legacy.encode(tx)
      {:ok, decoded} = Legacy.decode(encoded)
      assert decoded.to == nil
    end
  end

  describe "encode/1" do
    test "encode then decode roundtrip" do
      raw = Base.decode16!(@simple_tx_hex, case: :lower)
      {:ok, tx} = Legacy.decode(raw)
      re_encoded = Legacy.encode(tx)
      assert re_encoded == raw
    end
  end

  describe "signing_hash/1" do
    test "unsigned tx produces 32-byte signing hash" do
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower),
        value: 0,
        data: ""
      }

      hash = Legacy.signing_hash(tx)
      assert byte_size(hash) == 32
    end

    test "same tx produces same signing hash" do
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower),
        value: 0,
        data: ""
      }

      assert Legacy.signing_hash(tx) == Legacy.signing_hash(tx)
    end
  end
end
