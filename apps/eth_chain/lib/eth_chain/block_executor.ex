defmodule EthChain.BlockExecutor do
  @moduledoc """
  Executes blocks by coordinating validation and EVM execution.

  Orchestrates the full block execution pipeline: pre-execution validation,
  EVM environment construction, transaction execution, and post-execution
  verification.
  """

  alias EthChain.BlockValidator
  alias EthCore.Types.{Block, BlockHeader}
  alias EthVm.Types.{BlockExecutionResult, Environment}

  @doc """
  Executes a block: validates, runs transactions through EVM, verifies post-state.

  Steps:
  1. Validate header against parent (pre-execution)
  2. Validate body
  3. Build EVM environment from header
  4. Execute block through EVM
  5. Verify gas_used matches header
  6. Return execution result
  """
  @spec execute_block(Block.t(), BlockHeader.t(), module(), module()) ::
          {:ok, BlockExecutionResult.t()} | {:error, term()}
  def execute_block(%Block{} = block, %BlockHeader{} = parent_header, evm_module, state_provider) do
    with :ok <- BlockValidator.validate_header(block.header, parent_header),
         :ok <- BlockValidator.validate_body(block),
         {:ok, result} <- do_execute(block, evm_module, state_provider),
         :ok <- verify_gas_used(result.gas_used, block.header.gas_used) do
      {:ok, result}
    end
  end

  @doc """
  Builds an EVM Environment from a block header.

  Maps header fields to the corresponding Environment fields used
  by the EVM during transaction execution.
  """
  @spec build_environment(BlockHeader.t()) :: Environment.t()
  def build_environment(%BlockHeader{} = header) do
    %Environment{
      coinbase: header.coinbase,
      gas_limit: header.gas_limit,
      number: header.number,
      timestamp: header.timestamp,
      difficulty: header.difficulty,
      base_fee_per_gas: header.base_fee_per_gas || 0,
      chain_id: 1,
      block_hash_lookup: nil
    }
  end

  defp do_execute(block, evm_module, state_provider) do
    evm_module.execute_block(block, state_provider)
  end

  defp verify_gas_used(executed_gas, header_gas) do
    if executed_gas == header_gas do
      :ok
    else
      {:error, :gas_used_mismatch}
    end
  end
end
