defmodule EthChain.GasOracleTest do
  use ExUnit.Case, async: false

  alias EthChain.GasOracle
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthStorage.Store

  setup do
    name = :"gas_oracle_store_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Store.start_link(name: name)
    %{store: name}
  end

  defp make_header(number, opts \\ []) do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: number,
      gas_limit: Keyword.get(opts, :gas_limit, 30_000_000),
      gas_used: Keyword.get(opts, :gas_used, 0),
      timestamp: 1_000_000 + number,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: Keyword.get(opts, :base_fee_per_gas, 1_000_000_000),
      withdrawals_root: nil,
      blob_gas_used: nil,
      excess_blob_gas: nil,
      parent_beacon_block_root: nil,
      requests_hash: nil
    }
  end

  defp make_tx(gas_price, nonce \\ 0) do
    tx = %Transaction.Legacy{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, nonce + 1, gas_price + 1)
  end

  defp store_block(store, number, txs, opts \\ []) do
    header = make_header(number, opts)
    block = %Block{header: header, transactions: txs, ommers: []}
    {:ok, _hash} = EthStorage.BlockStore.store_block(block, store)
    Store.set_latest_block_number(store, number)
  end

  describe "suggest_gas_price/1" do
    test "returns fallback gas price when no blocks", %{store: store} do
      assert {:ok, 1_000_000_000} = GasOracle.suggest_gas_price(store)
    end

    test "returns reasonable estimate with stored blocks", %{store: store} do
      # Store a block with transactions at varying gas prices
      txs = [
        make_tx(2_000_000_000, 0),
        make_tx(3_000_000_000, 1),
        make_tx(5_000_000_000, 2)
      ]

      store_block(store, 0, txs)

      assert {:ok, price} = GasOracle.suggest_gas_price(store)
      assert is_integer(price)
      assert price > 0
      # Should be somewhere in the range of our tx gas prices
      assert price >= 2_000_000_000
      assert price <= 5_000_000_000
    end

    test "returns fallback when blocks have no transactions", %{store: store} do
      store_block(store, 0, [])
      assert {:ok, 1_000_000_000} = GasOracle.suggest_gas_price(store)
    end
  end

  describe "suggest_max_priority_fee/1" do
    test "returns fallback when no blocks", %{store: store} do
      assert {:ok, 1_000_000_000} = GasOracle.suggest_max_priority_fee(store)
    end

    test "returns estimate with stored blocks", %{store: store} do
      txs = [
        make_tx(2_000_000_000, 0),
        make_tx(4_000_000_000, 1)
      ]

      store_block(store, 0, txs, base_fee_per_gas: 1_000_000_000)

      assert {:ok, fee} = GasOracle.suggest_max_priority_fee(store)
      assert is_integer(fee)
      assert fee >= 0
    end
  end
end
