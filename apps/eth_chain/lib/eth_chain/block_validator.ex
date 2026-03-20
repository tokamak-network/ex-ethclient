defmodule EthChain.BlockValidator do
  @moduledoc """
  Pre-execution block validation.

  Validates block header fields and block body constraints that can be
  checked without executing transactions or accessing storage. All checks
  assume post-merge (Paris+) consensus rules.
  """

  alias EthCore.Types.{Block, BlockHeader}

  # keccak256(RLP([])) — the hash of an empty ommers list (post-merge constant)
  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  @max_extra_data_bytes 32

  @doc """
  Validates a block header against its parent header.

  Checks:
  - block number == parent number + 1
  - timestamp > parent timestamp
  - gas_used <= gas_limit
  - gas_limit within bounds of parent (plus or minus 1/1024)
  - extra_data <= 32 bytes
  - ommers_hash == empty list hash (post-merge)
  - difficulty == 0 (post-merge)
  - nonce == 0 (post-merge)
  """
  @spec validate_header(BlockHeader.t(), BlockHeader.t()) ::
          :ok | {:error, atom()}
  def validate_header(%BlockHeader{} = header, %BlockHeader{} = parent) do
    with :ok <- validate_block_number(header, parent),
         :ok <- validate_timestamp(header, parent),
         :ok <- validate_gas_used(header),
         :ok <- validate_gas_limit(header, parent),
         :ok <- validate_extra_data(header),
         :ok <- validate_ommers_hash(header),
         :ok <- validate_difficulty(header),
         :ok <- validate_nonce(header) do
      :ok
    end
  end

  @doc """
  Validates a block body.

  Checks:
  - ommers list is empty (post-merge)
  """
  @spec validate_body(Block.t()) :: :ok | {:error, atom()}
  def validate_body(%Block{ommers: ommers}) do
    if ommers == [] do
      :ok
    else
      {:error, :non_empty_ommers}
    end
  end

  defp validate_block_number(header, parent) do
    if header.number == parent.number + 1 do
      :ok
    else
      {:error, :invalid_block_number}
    end
  end

  defp validate_timestamp(header, parent) do
    if header.timestamp > parent.timestamp do
      :ok
    else
      {:error, :invalid_timestamp}
    end
  end

  defp validate_gas_used(header) do
    if header.gas_used <= header.gas_limit do
      :ok
    else
      {:error, :gas_used_exceeds_limit}
    end
  end

  defp validate_gas_limit(header, parent) do
    if EthChain.Gas.valid_gas_limit?(header.gas_limit, parent.gas_limit) do
      :ok
    else
      {:error, :invalid_gas_limit}
    end
  end

  defp validate_extra_data(header) do
    if byte_size(header.extra_data) <= @max_extra_data_bytes do
      :ok
    else
      {:error, :extra_data_too_long}
    end
  end

  defp validate_ommers_hash(header) do
    if header.ommers_hash == @empty_ommers_hash do
      :ok
    else
      {:error, :invalid_ommers_hash}
    end
  end

  defp validate_difficulty(header) do
    if header.difficulty == 0 do
      :ok
    else
      {:error, :invalid_difficulty}
    end
  end

  defp validate_nonce(header) do
    if header.nonce == <<0::64>> do
      :ok
    else
      {:error, :invalid_nonce}
    end
  end
end
