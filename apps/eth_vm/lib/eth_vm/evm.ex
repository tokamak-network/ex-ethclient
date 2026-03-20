defmodule EthVm.Evm do
  @moduledoc """
  Behaviour for EVM execution backends.

  Implementations must provide transaction and block execution.
  The mock implementation (`EthVm.Mock`) is used for testing chain
  orchestration without a real EVM. The production implementation
  will use a revm Rust NIF.
  """

  @doc """
  Executes a single signed transaction within the given environment.

  Returns an `ExecutionResult` on success or an error tuple.
  """
  @callback execute_transaction(
              env :: EthVm.Types.Environment.t(),
              tx :: EthCore.Types.SignedTransaction.t(),
              state_provider :: module()
            ) ::
              {:ok, EthVm.Types.ExecutionResult.t()}
              | {:error, term()}

  @doc """
  Executes all transactions in a block.

  Returns a `BlockExecutionResult` containing receipts,
  total gas used, account updates, and aggregated logs.
  """
  @callback execute_block(
              block :: EthCore.Types.Block.t(),
              state_provider :: module()
            ) ::
              {:ok, EthVm.Types.BlockExecutionResult.t()}
              | {:error, term()}
end
