defmodule EthVm.Mock do
  @moduledoc """
  Mock EVM implementation for testing chain orchestration.

  Returns successful results with standard gas costs without
  performing actual EVM execution.
  """

  @behaviour EthVm.Evm

  alias EthVm.Constants
  alias EthVm.Types.{BlockExecutionResult, ExecutionResult}

  @impl true
  @doc """
  Returns a mock successful execution result with gas_used = 21_000.
  """
  @spec execute_transaction(
          EthVm.Types.Environment.t(),
          EthCore.Types.SignedTransaction.t(),
          module()
        ) :: {:ok, ExecutionResult.t()}
  def execute_transaction(_env, _tx, _state_provider) do
    result = %ExecutionResult{
      success: true,
      gas_used: Constants.tx_gas_cost(),
      gas_refunded: 0,
      output: <<>>,
      logs: [],
      error: nil
    }

    {:ok, result}
  end

  @impl true
  @doc """
  Executes a block by producing a mock receipt for each transaction.

  Processes transactions sequentially with state threading: each
  transaction sees the accumulated state from prior transactions.
  Builds mock account updates based on sender/receiver addresses.
  """
  @spec execute_block(EthCore.Types.Block.t(), module()) ::
          {:ok, BlockExecutionResult.t()}
  def execute_block(block, _state_provider) do
    txs = block.transactions

    {receipts, total_gas, account_updates} =
      txs
      |> Enum.with_index()
      |> Enum.reduce({[], 0, %{}}, fn {tx, _idx}, {receipts, acc_gas, state} ->
        gas = Constants.tx_gas_cost()
        cumulative = acc_gas + gas

        receipt = %EthCore.Types.Receipt{
          type: tx_type(tx),
          status: 1,
          cumulative_gas_used: cumulative,
          logs_bloom: <<0::2048>>,
          logs: []
        }

        new_state = mock_state_update(state, tx)
        {[receipt | receipts], cumulative, new_state}
      end)

    result = %BlockExecutionResult{
      receipts: Enum.reverse(receipts),
      gas_used: total_gas,
      account_updates: account_updates,
      logs: []
    }

    {:ok, result}
  end

  @spec tx_type(struct()) :: non_neg_integer()
  defp tx_type(%EthCore.Types.SignedTransaction{tx: inner}), do: tx_type_inner(inner)
  defp tx_type(_), do: 0

  @spec tx_type_inner(struct()) :: non_neg_integer()
  defp tx_type_inner(%EthCore.Types.Transaction.Legacy{}), do: 0
  defp tx_type_inner(%EthCore.Types.Transaction.EIP2930{}), do: 1
  defp tx_type_inner(%EthCore.Types.Transaction.EIP1559{}), do: 2
  defp tx_type_inner(%EthCore.Types.Transaction.EIP4844{}), do: 3
  defp tx_type_inner(%EthCore.Types.Transaction.EIP7702{}), do: 4
  defp tx_type_inner(_), do: 0

  # Builds mock account state updates from a transaction. Increments the
  # sender nonce and adjusts balances by the transferred value.
  @spec mock_state_update(map(), struct()) :: map()
  defp mock_state_update(state, %EthCore.Types.SignedTransaction{tx: inner}) do
    from = Map.get(inner, :from, <<0::160>>)
    to = Map.get(inner, :to, <<0::160>>) || <<0::160>>
    value = Map.get(inner, :value, 0)

    sender = Map.get(state, from, %{nonce: 0, balance: 0, code: nil, storage: %{}})
    receiver = Map.get(state, to, %{nonce: 0, balance: 0, code: nil, storage: %{}})

    updated_sender = %{sender | nonce: sender.nonce + 1, balance: sender.balance - value}
    updated_receiver = %{receiver | balance: receiver.balance + value}

    state
    |> Map.put(from, updated_sender)
    |> Map.put(to, updated_receiver)
  end

  defp mock_state_update(state, _tx), do: state
end
