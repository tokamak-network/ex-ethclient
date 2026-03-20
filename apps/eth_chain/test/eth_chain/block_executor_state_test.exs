defmodule EthChain.BlockExecutorStateTest do
  use ExUnit.Case, async: false

  alias EthChain.BlockExecutor
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthStorage.MPT.Trie
  alias EthVm.Types.BlockExecutionResult

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  # Mock EVM that returns account_updates
  defmodule MockEvmWithUpdates do
    @moduledoc false
    @behaviour EthVm.Evm

    @impl true
    def execute_transaction(_env, _tx, _state_provider) do
      {:ok, %EthVm.Types.ExecutionResult{success: true, gas_used: 21_000}}
    end

    @impl true
    def execute_block(block, _state_provider) do
      gas_used = length(block.transactions) * 21_000

      receipts =
        block.transactions
        |> Enum.with_index()
        |> Enum.map(fn {_tx, idx} ->
          %EthCore.Types.Receipt{
            type: 0,
            status: 1,
            cumulative_gas_used: (idx + 1) * 21_000,
            logs_bloom: <<0::2048>>,
            logs: []
          }
        end)

      updates = %{
        <<1::160>> => %{nonce: 1, balance: 900_000, code: nil, storage: %{}},
        <<2::160>> => %{nonce: 0, balance: 100_000, code: nil, storage: %{}}
      }

      {:ok,
       %BlockExecutionResult{
         receipts: receipts,
         gas_used: gas_used,
         account_updates: updates,
         logs: []
       }}
    end
  end

  defp valid_parent do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 100,
      gas_limit: 30_000_000,
      gas_used: 15_000_000,
      timestamp: 1_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000
    }
  end

  defp sample_tx do
    tx = %Transaction.Legacy{
      nonce: 0,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, 1, 1)
  end

  setup do
    {:ok, store} = EthStorage.Store.start_link(name: :"store_#{:erlang.unique_integer()}")
    {:ok, store: store}
  end

  describe "execute_and_apply/5" do
    test "executes block and computes state root", %{store: store} do
      parent = valid_parent()
      tx = sample_tx()

      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 101,
        gas_limit: 30_000_000,
        gas_used: 21_000,
        timestamp: 1_000_012,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 1_000_000_000
      }

      block = %Block{header: header, transactions: [tx], ommers: []}

      assert {:ok, result, state_root} =
               BlockExecutor.execute_and_apply(
                 block,
                 parent,
                 MockEvmWithUpdates,
                 nil,
                 store
               )

      assert %BlockExecutionResult{} = result
      assert result.gas_used == 21_000
      assert byte_size(state_root) == 32
      # State root should not be empty since we have account updates
      assert state_root != Trie.empty_root_hash()
    end

    test "returns empty trie root with no account updates", %{store: store} do
      parent = valid_parent()

      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 101,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: 1_000_012,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 1_000_000_000
      }

      block = %Block{header: header, transactions: [], ommers: []}

      assert {:ok, _result, state_root} =
               BlockExecutor.execute_and_apply(block, parent, EthVm.Mock, nil, store)

      assert state_root == Trie.empty_root_hash()
    end
  end
end
