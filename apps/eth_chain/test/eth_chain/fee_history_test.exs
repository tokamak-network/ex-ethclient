defmodule EthChain.FeeHistoryTest do
  use ExUnit.Case, async: false

  alias EthChain.FeeHistory
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthStorage.Store

  setup do
    name = :"fee_history_store_#{:erlang.unique_integer([:positive])}"
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

  describe "get_fee_history/4" do
    test "returns correct structure", %{store: store} do
      store_block(store, 0, [], gas_used: 5_000_000, gas_limit: 30_000_000)

      assert {:ok, result} = FeeHistory.get_fee_history(1, :latest, [25.0, 75.0], store)

      assert Map.has_key?(result, "oldestBlock")
      assert Map.has_key?(result, "baseFeePerGas")
      assert Map.has_key?(result, "gasUsedRatio")
      assert Map.has_key?(result, "reward")

      assert is_list(result["baseFeePerGas"])
      assert is_list(result["gasUsedRatio"])
      assert is_list(result["reward"])
    end

    test "base_fee_per_gas has block_count + 1 entries", %{store: store} do
      store_block(store, 0, [], base_fee_per_gas: 1_000_000_000)
      store_block(store, 1, [], base_fee_per_gas: 1_100_000_000)
      store_block(store, 2, [], base_fee_per_gas: 1_200_000_000)

      assert {:ok, result} = FeeHistory.get_fee_history(3, :latest, [], store)

      # block_count = 3, so baseFeePerGas should have 4 entries
      assert length(result["baseFeePerGas"]) == 4
      assert length(result["gasUsedRatio"]) == 3
    end

    test "handles empty block range", %{store: store} do
      store_block(store, 0, [])

      assert {:ok, result} = FeeHistory.get_fee_history(1, 0, [], store)
      assert result["oldestBlock"] == "0x0"
      assert length(result["baseFeePerGas"]) == 2
      assert length(result["gasUsedRatio"]) == 1
    end

    test "includes reward percentiles", %{store: store} do
      txs = [
        make_tx(2_000_000_000, 0),
        make_tx(3_000_000_000, 1),
        make_tx(5_000_000_000, 2)
      ]

      store_block(store, 0, txs, base_fee_per_gas: 1_000_000_000)

      assert {:ok, result} = FeeHistory.get_fee_history(1, :latest, [25.0, 75.0], store)

      assert length(result["reward"]) == 1
      [block_rewards] = result["reward"]
      assert length(block_rewards) == 2
      # Each reward should be a hex string
      assert Enum.all?(block_rewards, &String.starts_with?(&1, "0x"))
    end
  end
end
