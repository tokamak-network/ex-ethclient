defmodule EthVm.BlockExecutionTest do
  use ExUnit.Case, async: true

  alias EthVm.Mock
  alias EthVm.Types.BlockExecutionResult

  # A stateful mock EVM that threads state across transactions within a block.
  # Uses the process dictionary to accumulate state, simulating how a real
  # EVM threads state changes across transactions in the same block.
  defmodule StatefulMockEvm do
    @moduledoc false
    @behaviour EthVm.Evm

    @impl true
    def execute_transaction(_env, signed_tx, _state_provider) do
      tx = signed_tx.tx
      to = Map.get(tx, :to, <<0::160>>) || <<0::160>>
      value = Map.get(tx, :value, 0)

      # Read accumulated state from process dictionary
      state = Process.get(:mock_state, %{})
      tx_index = Process.get(:mock_tx_index, 0)

      # The receiver balance reflects previous txs
      receiver = Map.get(state, to, %{nonce: 0, balance: 0})
      new_receiver = %{receiver | balance: receiver.balance + value}
      new_state = Map.put(state, to, new_receiver)

      Process.put(:mock_state, new_state)
      Process.put(:mock_tx_index, tx_index + 1)

      # Encode the receiver's balance BEFORE this tx in the output,
      # so tests can verify state was visible
      result = %EthVm.Types.ExecutionResult{
        success: true,
        gas_used: 21_000,
        gas_refunded: 0,
        output: <<receiver.balance::256>>,
        logs: [],
        error: nil
      }

      {:ok, result}
    end

    @impl true
    def execute_block(block, state_provider) do
      # Clear state before block execution
      Process.put(:mock_state, %{})
      Process.put(:mock_tx_index, 0)

      txs = block.transactions

      {receipts, total_gas, all_logs} =
        Enum.reduce(txs, {[], 0, []}, fn tx, {receipts, acc_gas, logs} ->
          {:ok, exec_result} = execute_transaction(nil, tx, state_provider)
          cumulative = acc_gas + exec_result.gas_used

          receipt = %EthCore.Types.Receipt{
            type: 0,
            status: if(exec_result.success, do: 1, else: 0),
            cumulative_gas_used: cumulative,
            logs_bloom: <<0::2048>>,
            logs: exec_result.logs
          }

          {[receipt | receipts], cumulative, logs ++ exec_result.logs}
        end)

      final_state = Process.get(:mock_state, %{})

      account_updates =
        Enum.into(final_state, %{}, fn {addr, acct} ->
          {addr, %{nonce: acct.nonce, balance: acct.balance, code: nil, storage: %{}}}
        end)

      result = %BlockExecutionResult{
        receipts: Enum.reverse(receipts),
        gas_used: total_gas,
        account_updates: account_updates,
        logs: all_logs
      }

      {:ok, result}
    end
  end

  defp mock_signed_tx(to \\ <<2::160>>, value \\ 0) do
    tx = %EthCore.Types.Transaction.Legacy{
      nonce: 0,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      to: to,
      value: value,
      data: <<>>
    }

    %EthCore.Types.SignedTransaction{tx: tx, v: 27, r: 1, s: 1}
  end

  defp mock_block(txs) do
    header = %EthCore.Types.BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 1,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_700_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }

    %EthCore.Types.Block{header: header, transactions: txs}
  end

  describe "block execution with state threading" do
    test "block with 2 txs to same address: tx2 sees tx1 balance change" do
      receiver = <<2::160>>
      tx1 = mock_signed_tx(receiver, 100)
      tx2 = mock_signed_tx(receiver, 200)
      block = mock_block([tx1, tx2])

      assert {:ok, %BlockExecutionResult{} = result} =
               StatefulMockEvm.execute_block(block, nil)

      assert length(result.receipts) == 2

      # Account updates should reflect both tx's effects
      assert Map.has_key?(result.account_updates, receiver)
      # 100 from tx1 + 200 from tx2
      assert result.account_updates[receiver].balance == 300
    end

    test "cumulative gas is correct across transactions" do
      tx1 = mock_signed_tx()
      tx2 = mock_signed_tx()
      tx3 = mock_signed_tx()
      block = mock_block([tx1, tx2, tx3])

      assert {:ok, %BlockExecutionResult{} = result} =
               StatefulMockEvm.execute_block(block, nil)

      assert result.gas_used == 63_000

      [r1, r2, r3] = result.receipts
      assert r1.cumulative_gas_used == 21_000
      assert r2.cumulative_gas_used == 42_000
      assert r3.cumulative_gas_used == 63_000
    end

    test "account updates reflect all transactions" do
      addr_a = <<3::160>>
      addr_b = <<4::160>>
      tx1 = mock_signed_tx(addr_a, 50)
      tx2 = mock_signed_tx(addr_b, 75)
      tx3 = mock_signed_tx(addr_a, 25)
      block = mock_block([tx1, tx2, tx3])

      assert {:ok, %BlockExecutionResult{} = result} =
               StatefulMockEvm.execute_block(block, nil)

      # addr_a received 50 + 25 = 75
      assert result.account_updates[addr_a].balance == 75
      # addr_b received 75
      assert result.account_updates[addr_b].balance == 75
    end
  end

  describe "Mock.execute_block/2 state threading" do
    test "mock produces account updates with state changes" do
      receiver = <<2::160>>
      tx1 = mock_signed_tx(receiver, 100)
      tx2 = mock_signed_tx(receiver, 200)
      block = mock_block([tx1, tx2])

      assert {:ok, %BlockExecutionResult{} = result} = Mock.execute_block(block, nil)

      assert Map.has_key?(result.account_updates, receiver)
      # receiver got 100 + 200 = 300
      assert result.account_updates[receiver].balance == 300
    end

    test "mock produces correct cumulative gas" do
      txs = [mock_signed_tx(), mock_signed_tx()]
      block = mock_block(txs)

      assert {:ok, %BlockExecutionResult{} = result} = Mock.execute_block(block, nil)
      assert result.gas_used == 42_000

      [r1, r2] = result.receipts
      assert r1.cumulative_gas_used == 21_000
      assert r2.cumulative_gas_used == 42_000
    end

    test "empty block produces no updates" do
      block = mock_block([])

      assert {:ok, %BlockExecutionResult{} = result} = Mock.execute_block(block, nil)
      assert result.gas_used == 0
      assert result.receipts == []
      assert result.account_updates == %{}
    end
  end
end
