defmodule EthChain.Chain do
  @moduledoc """
  Main chain orchestrator.

  Coordinates block validation, execution, and payload building by
  delegating to specialized modules.
  """

  alias EthChain.{BlockExecutor, BlockValidator, PayloadBuilder}
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction}
  alias EthVm.Types.BlockExecutionResult

  @doc """
  Validates a block against its parent header (pre-execution only).

  Runs both header validation and body validation. Returns `:ok` if all
  checks pass, or `{:error, reason}` on the first failure.
  """
  @spec validate_block(Block.t(), BlockHeader.t()) ::
          :ok | {:error, atom()}
  def validate_block(%Block{} = block, %BlockHeader{} = parent_header) do
    with :ok <- BlockValidator.validate_header(block.header, parent_header),
         :ok <- BlockValidator.validate_body(block) do
      :ok
    end
  end

  @doc """
  Processes a new block: validate + execute.

  Delegates to `BlockExecutor.execute_block/4` which performs full
  pre-execution validation followed by EVM execution and post-execution
  gas verification.
  """
  @spec process_block(Block.t(), BlockHeader.t(), keyword()) ::
          {:ok, BlockExecutionResult.t()} | {:error, term()}
  def process_block(%Block{} = block, %BlockHeader{} = parent_header, opts \\ []) do
    evm_module = Keyword.get(opts, :evm, EthVm.Mock)
    state_provider = Keyword.get(opts, :state_provider)

    BlockExecutor.execute_block(block, parent_header, evm_module, state_provider)
  end

  @doc """
  Builds a new block from pending transactions.

  Delegates to `PayloadBuilder.build_payload/6` which selects transactions,
  computes header fields, and executes the block through the EVM.
  """
  @spec build_block(
          BlockHeader.t(),
          <<_::160>>,
          non_neg_integer(),
          [SignedTransaction.t()],
          keyword()
        ) ::
          {:ok, Block.t(), BlockExecutionResult.t()} | {:error, term()}
  def build_block(
        %BlockHeader{} = parent_header,
        coinbase,
        timestamp,
        transactions,
        opts \\ []
      ) do
    evm_module = Keyword.get(opts, :evm, EthVm.Mock)
    state_provider = Keyword.get(opts, :state_provider)

    PayloadBuilder.build_payload(
      parent_header,
      coinbase,
      timestamp,
      transactions,
      evm_module,
      state_provider
    )
  end
end
