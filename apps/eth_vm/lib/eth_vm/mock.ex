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
  """
  @spec execute_block(EthCore.Types.Block.t(), module()) ::
          {:ok, BlockExecutionResult.t()}
  def execute_block(block, _state_provider) do
    txs = block.transactions

    {receipts, total_gas} =
      txs
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {_tx, _idx}, acc_gas ->
        gas = Constants.tx_gas_cost()
        cumulative = acc_gas + gas

        receipt = %EthCore.Types.Receipt{
          type: 0,
          status: 1,
          cumulative_gas_used: cumulative,
          logs_bloom: <<0::2048>>,
          logs: []
        }

        {receipt, cumulative}
      end)

    result = %BlockExecutionResult{
      receipts: receipts,
      gas_used: total_gas,
      account_updates: %{},
      logs: []
    }

    {:ok, result}
  end
end
