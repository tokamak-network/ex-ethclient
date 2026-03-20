defmodule EthChain.Chain do
  @moduledoc """
  Main chain orchestrator.

  Coordinates block validation by delegating to specialized modules.
  Currently supports pre-execution validation only (no EVM or storage needed).
  """

  alias EthChain.BlockValidator
  alias EthCore.Types.{Block, BlockHeader}

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
end
