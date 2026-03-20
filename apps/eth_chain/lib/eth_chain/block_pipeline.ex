defmodule EthChain.BlockPipeline do
  @moduledoc "Processes incoming blocks from the network layer."

  alias EthChain.{Chain, Mempool}
  alias EthCore.Types.Block
  alias EthStorage.BlockStore

  @doc """
  Processes a new block received from a peer.

  1. Get parent header from storage
  2. Validate + execute the block
  3. Store the block if valid
  4. Remove included transactions from mempool
  5. Update latest block number
  """
  @spec process_new_block(Block.t(), GenServer.server(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def process_new_block(%Block{} = block, store, opts \\ []) do
    mempool = Keyword.get(opts, :mempool)

    with {:ok, parent_header} <- fetch_parent_header(block, store),
         {:ok, _result} <- Chain.process_block(block, parent_header, opts),
         {:ok, block_hash} <- BlockStore.store_block(block, store),
         :ok <- EthStorage.Store.set_latest_block_number(store, block.header.number) do
      if mempool, do: Mempool.remove_block_transactions(block, mempool)
      {:ok, block_hash}
    end
  end

  @doc """
  Processes a batch of blocks (for sync).

  Processes blocks sequentially in order. Returns the count of
  successfully processed blocks, or an error on the first failure.
  """
  @spec process_blocks([Block.t()], GenServer.server(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def process_blocks(blocks, store, opts \\ []) do
    do_process_blocks(blocks, store, opts, 0)
  end

  @spec do_process_blocks([Block.t()], GenServer.server(), keyword(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp do_process_blocks([], _store, _opts, count), do: {:ok, count}

  defp do_process_blocks([block | rest], store, opts, count) do
    case process_new_block(block, store, opts) do
      {:ok, _hash} -> do_process_blocks(rest, store, opts, count + 1)
      {:error, _} = err -> err
    end
  end

  @spec fetch_parent_header(Block.t(), GenServer.server()) ::
          {:ok, EthCore.Types.BlockHeader.t()} | {:error, atom()}
  defp fetch_parent_header(%Block{header: header}, store) do
    parent_hash = header.parent_hash

    case BlockStore.get_header(parent_hash, store) do
      {:ok, nil} -> {:error, :parent_not_found}
      {:ok, parent_header} -> {:ok, parent_header}
      {:error, _} = err -> err
    end
  end

  defp fetch_parent_header(_, _store), do: {:error, :invalid_block}
end
