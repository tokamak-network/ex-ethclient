defmodule EthChain.BlockPipeline do
  @moduledoc """
  Processes incoming blocks from the network layer.

  `process_block/2` is the single entry point that validates, executes,
  stores, indexes transactions, stores receipts, and updates the latest
  block number.
  """

  alias EthChain.{BlockExecutor, Chain, Mempool}
  alias EthCore.Types.{Block, SignedTransaction}
  alias EthStorage.{BlockStore, Store}

  @doc """
  Process a new block: validate, execute, store, index.

  This is the unified entry point for all block processing, whether
  blocks come from sync, Engine API, or peer announcements.

  Steps:
  1. Get parent header from storage
  2. Validate + execute the block
  3. Store the block (header + body + canonical hash)
  4. Store receipts for each transaction
  5. Index transaction hashes
  6. Update latest block number
  """
  @spec process_block(Block.t(), GenServer.server(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def process_block(%Block{} = block, store \\ Store, opts \\ []) do
    mempool = Keyword.get(opts, :mempool)

    with {:ok, parent_header} <- fetch_parent_header(block, store),
         {:ok, result} <- Chain.process_block(block, parent_header, opts),
         {:ok, block_hash} <- BlockStore.store_block(block, store),
         :ok <- store_receipts(block_hash, result.receipts, store),
         :ok <- index_transactions(block_hash, block, store),
         :ok <- Store.set_latest_block_number(store, block.header.number) do
      if mempool, do: Mempool.remove_block_transactions(block, mempool)
      {:ok, block_hash}
    end
  end

  @doc """
  Processes a new block received from a peer.

  Delegates to `process_block/3` for the full pipeline.
  """
  @spec process_new_block(Block.t(), GenServer.server(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def process_new_block(%Block{} = block, store, opts \\ []) do
    process_block(block, store, opts)
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

  @doc """
  Processes a block with full state transition and root verification.

  1. Fetches the parent header from storage
  2. Executes the block and applies state transitions
  3. Verifies the computed state_root matches the header state_root
  4. Stores the block, receipts, and tx index
  """
  @spec process_with_state(Block.t(), GenServer.server(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def process_with_state(%Block{} = block, store, opts \\ []) do
    evm_module = Keyword.get(opts, :evm, EthVm.Mock)
    state_provider = Keyword.get(opts, :state_provider)

    with {:ok, parent_header} <- fetch_parent_header(block, store),
         {:ok, result, computed_root} <-
           BlockExecutor.execute_and_apply(
             block,
             parent_header,
             evm_module,
             state_provider,
             store
           ),
         :ok <- verify_state_root(computed_root, block.header.state_root),
         {:ok, block_hash} <- BlockStore.store_block(block, store),
         :ok <- store_receipts(block_hash, result.receipts, store),
         :ok <- index_transactions(block_hash, block, store),
         :ok <- Store.set_latest_block_number(store, block.header.number) do
      {:ok, block_hash}
    end
  end

  # -- Private helpers --------------------------------------------------------

  @spec store_receipts(<<_::256>>, [EthCore.Types.Receipt.t()], GenServer.server()) :: :ok
  defp store_receipts(block_hash, receipts, store) do
    receipts
    |> Enum.with_index()
    |> Enum.each(fn {receipt, idx} ->
      encoded = :erlang.term_to_binary(receipt)
      Store.put_receipt(store, block_hash, idx, encoded)
    end)

    :ok
  end

  @spec index_transactions(<<_::256>>, Block.t(), GenServer.server()) :: :ok
  defp index_transactions(block_hash, block, store) do
    block.transactions
    |> Enum.with_index()
    |> Enum.each(fn {signed_tx, idx} ->
      tx_hash = SignedTransaction.tx_hash(signed_tx)
      Store.put_tx_location(store, tx_hash, block_hash, idx)
    end)

    :ok
  end

  @spec do_process_blocks([Block.t()], GenServer.server(), keyword(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp do_process_blocks([], _store, _opts, count), do: {:ok, count}

  defp do_process_blocks([block | rest], store, opts, count) do
    case process_block(block, store, opts) do
      {:ok, _hash} -> do_process_blocks(rest, store, opts, count + 1)
      {:error, _} = err -> err
    end
  end

  @spec verify_state_root(<<_::256>>, <<_::256>>) :: :ok | {:error, atom()}
  defp verify_state_root(computed, expected) do
    if computed == expected do
      :ok
    else
      {:error, :state_root_mismatch}
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
