defmodule EthChain.GasTest do
  use ExUnit.Case, async: true

  alias EthChain.Gas
  alias EthCore.Types.{SignedTransaction, Transaction}

  defp signed(tx) do
    SignedTransaction.new(tx, 27, 1, 1)
  end

  describe "intrinsic_gas/1 for legacy transactions" do
    test "simple transfer (no data)" do
      tx =
        signed(%Transaction.Legacy{
          nonce: 0,
          gas_price: 1,
          gas_limit: 21_000,
          to: <<1::160>>,
          value: 0,
          data: <<>>
        })

      assert Gas.intrinsic_gas(tx) == 21_000
    end

    test "transfer with calldata" do
      # 2 zero bytes + 3 non-zero bytes = 2*4 + 3*16 = 56
      tx =
        signed(%Transaction.Legacy{
          nonce: 0,
          gas_price: 1,
          gas_limit: 100_000,
          to: <<1::160>>,
          value: 0,
          data: <<0, 0, 1, 2, 3>>
        })

      assert Gas.intrinsic_gas(tx) == 21_000 + 2 * 4 + 3 * 16
    end

    test "contract creation" do
      # 32 bytes of init code = 1 word, cost = 53000 + 0 (all zeros data cost 32*4) + 1*2
      tx =
        signed(%Transaction.Legacy{
          nonce: 0,
          gas_price: 1,
          gas_limit: 100_000,
          to: nil,
          value: 0,
          data: :binary.copy(<<0>>, 32)
        })

      # base: 53000, data: 32*4=128, init_code: ceil(32/32)*2=2
      assert Gas.intrinsic_gas(tx) == 53_000 + 128 + 2
    end

    test "contract creation with non-aligned init code" do
      # 33 bytes = ceil(33/32) = 2 words
      tx =
        signed(%Transaction.Legacy{
          nonce: 0,
          gas_price: 1,
          gas_limit: 100_000,
          to: nil,
          value: 0,
          data: :binary.copy(<<1>>, 33)
        })

      # base: 53000, data: 33*16=528, init_code: 2*2=4
      assert Gas.intrinsic_gas(tx) == 53_000 + 528 + 4
    end
  end

  describe "intrinsic_gas/1 for EIP-2930 transactions" do
    test "with access list" do
      address = <<1::160>>
      storage_key = <<1::256>>

      tx =
        signed(%Transaction.EIP2930{
          chain_id: 1,
          nonce: 0,
          gas_price: 1,
          gas_limit: 100_000,
          to: <<2::160>>,
          value: 0,
          data: <<>>,
          access_list: [{address, [storage_key]}]
        })

      # base: 21000, access_list: 2400 + 1*1900 = 4300
      assert Gas.intrinsic_gas(tx) == 21_000 + 2_400 + 1_900
    end

    test "with multiple access list entries" do
      tx =
        signed(%Transaction.EIP2930{
          chain_id: 1,
          nonce: 0,
          gas_price: 1,
          gas_limit: 100_000,
          to: <<2::160>>,
          value: 0,
          data: <<>>,
          access_list: [
            {<<1::160>>, [<<1::256>>, <<2::256>>]},
            {<<2::160>>, []}
          ]
        })

      # 2 addresses * 2400 = 4800, 2 keys * 1900 = 3800
      assert Gas.intrinsic_gas(tx) == 21_000 + 2 * 2_400 + 2 * 1_900
    end
  end

  describe "intrinsic_gas/1 for EIP-1559 transactions" do
    test "simple transfer" do
      tx =
        signed(%Transaction.EIP1559{
          chain_id: 1,
          nonce: 0,
          max_priority_fee_per_gas: 1,
          max_fee_per_gas: 100,
          gas_limit: 21_000,
          to: <<1::160>>,
          value: 0,
          data: <<>>,
          access_list: []
        })

      assert Gas.intrinsic_gas(tx) == 21_000
    end
  end

  describe "intrinsic_gas/1 for EIP-4844 transactions" do
    test "blob transaction with data" do
      tx =
        signed(%Transaction.EIP4844{
          chain_id: 1,
          nonce: 0,
          max_priority_fee_per_gas: 1,
          max_fee_per_gas: 100,
          gas_limit: 100_000,
          to: <<1::160>>,
          value: 0,
          data: <<1, 2, 3>>,
          access_list: [],
          max_fee_per_blob_gas: 1,
          blob_versioned_hashes: [<<1::256>>]
        })

      # base: 21000, data: 3*16=48
      assert Gas.intrinsic_gas(tx) == 21_000 + 48
    end
  end

  describe "valid_gas_limit?/2" do
    test "accepts same gas limit" do
      # diff = 0 < 30_000_000/1024 = 29296
      assert Gas.valid_gas_limit?(30_000_000, 30_000_000)
    end

    test "accepts gas limit within bounds" do
      parent = 30_000_000
      bound = div(parent, 1024)
      assert Gas.valid_gas_limit?(parent + bound - 1, parent)
      assert Gas.valid_gas_limit?(parent - bound + 1, parent)
    end

    test "rejects gas limit at exact boundary" do
      parent = 30_000_000
      bound = div(parent, 1024)
      refute Gas.valid_gas_limit?(parent + bound, parent)
      refute Gas.valid_gas_limit?(parent - bound, parent)
    end

    test "rejects gas limit below minimum" do
      refute Gas.valid_gas_limit?(4999, 5120)
    end
  end
end
