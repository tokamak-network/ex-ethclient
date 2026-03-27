defmodule EthStorage.Pruner do
  @moduledoc """
  Periodically prunes old state trie nodes to prevent unbounded disk growth.

  Tracks which trie node hashes belong to each block via a reference table.
  When a new block is finalized, marks older blocks (beyond the retention
  window) as prunable. A periodic pruning cycle deletes unreferenced trie
  nodes from both `:account_trie_nodes` and `:storage_trie_nodes` tables.

  ## Configuration

      config :eth_storage,
        pruning: true,
        retain_blocks: 128

  ## Strategy

  Keep state for the last N blocks (configurable, default 128). When a new
  block arrives via `notify_new_block/2`, record the block's state root.
  During `prune/0`, find blocks older than `(latest - retain_blocks)` and
  delete their trie nodes (only if not referenced by any retained block).
  """

  use GenServer

  alias EthStorage.Store

  require Logger

  @default_retain_blocks 128
  @default_prune_interval_ms 60_000

  @type stats :: %{
          pruned_count: non_neg_integer(),
          retained_blocks: non_neg_integer(),
          latest_block: non_neg_integer() | nil,
          last_pruned_at: DateTime.t() | nil
        }

  # --- Public API ---

  @doc "Starts the Pruner GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Notifies the pruner that a new block has been processed.

  Records the block number and its associated state root hash so the
  pruner knows which trie nodes are still needed.
  """
  @spec notify_new_block(GenServer.server(), non_neg_integer(), <<_::256>>) :: :ok
  def notify_new_block(server \\ __MODULE__, block_number, state_root) do
    GenServer.cast(server, {:new_block, block_number, state_root})
  end

  @doc """
  Registers trie node hashes that were created or updated during
  processing of the given block number.

  This must be called during block execution to track which nodes
  belong to which block for reference-counted pruning.
  """
  @spec track_trie_nodes(GenServer.server(), non_neg_integer(), [binary()]) :: :ok
  def track_trie_nodes(server \\ __MODULE__, block_number, node_hashes) do
    GenServer.cast(server, {:track_nodes, block_number, node_hashes})
  end

  @doc "Triggers a pruning cycle synchronously. Returns the number of nodes pruned."
  @spec prune(GenServer.server()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune(server \\ __MODULE__) do
    GenServer.call(server, :prune, :infinity)
  end

  @doc "Returns pruning statistics."
  @spec stats(GenServer.server()) :: {:ok, stats()}
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    retain_blocks = Keyword.get(opts, :retain_blocks, @default_retain_blocks)
    store = Keyword.get(opts, :store, EthStorage.Store)
    prune_interval = Keyword.get(opts, :prune_interval_ms, @default_prune_interval_ms)
    auto_prune = Keyword.get(opts, :auto_prune, true)

    # ETS table for block_number -> MapSet of node hashes
    refs_table = :ets.new(:block_state_refs, [:set, :private])
    # ETS table for block_number -> state_root
    roots_table = :ets.new(:block_roots, [:ordered_set, :private])

    state = %{
      retain_blocks: retain_blocks,
      store: store,
      refs_table: refs_table,
      roots_table: roots_table,
      latest_block: nil,
      pruned_count: 0,
      last_pruned_at: nil,
      prune_interval: prune_interval
    }

    if auto_prune do
      schedule_prune(prune_interval)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast({:new_block, block_number, state_root}, state) do
    :ets.insert(state.roots_table, {block_number, state_root})

    new_latest =
      case state.latest_block do
        nil -> block_number
        current -> max(current, block_number)
      end

    {:noreply, %{state | latest_block: new_latest}}
  end

  @impl true
  def handle_cast({:track_nodes, block_number, node_hashes}, state) do
    existing =
      case :ets.lookup(state.refs_table, block_number) do
        [{^block_number, set}] -> set
        [] -> MapSet.new()
      end

    updated = Enum.reduce(node_hashes, existing, &MapSet.put(&2, &1))
    :ets.insert(state.refs_table, {block_number, updated})
    {:noreply, state}
  end

  @impl true
  def handle_call(:prune, _from, state) do
    {count, new_state} = do_prune(state)
    {:reply, {:ok, count}, new_state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    retained =
      case state.latest_block do
        nil ->
          0

        latest ->
          cutoff = max(latest - state.retain_blocks, 0)

          :ets.select_count(state.roots_table, [
            {{:"$1", :_}, [{:>=, :"$1", cutoff}], [true]}
          ])
      end

    stats = %{
      pruned_count: state.pruned_count,
      retained_blocks: retained,
      latest_block: state.latest_block,
      last_pruned_at: state.last_pruned_at
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_info(:auto_prune, state) do
    {_count, new_state} = do_prune(state)
    schedule_prune(state.prune_interval)
    {:noreply, new_state}
  end

  # --- Private helpers ---

  @spec do_prune(map()) :: {non_neg_integer(), map()}
  defp do_prune(%{latest_block: nil} = state), do: {0, state}

  defp do_prune(state) do
    %{
      latest_block: latest,
      retain_blocks: retain,
      refs_table: refs_table,
      roots_table: roots_table,
      store: store,
      pruned_count: total_pruned
    } = state

    cutoff = max(latest - retain, 0)

    # Find all block numbers older than cutoff
    old_blocks = collect_old_blocks(roots_table, cutoff)

    if old_blocks == [] do
      {0, state}
    else
      # Collect node hashes referenced by retained blocks
      retained_nodes = collect_retained_nodes(refs_table, cutoff)

      # Collect and prune nodes from old blocks
      pruned =
        Enum.reduce(old_blocks, 0, fn block_num, acc ->
          case :ets.lookup(refs_table, block_num) do
            [{^block_num, node_set}] ->
              prunable =
                node_set
                |> MapSet.difference(retained_nodes)
                |> MapSet.to_list()

              Enum.each(prunable, fn hash ->
                Store.delete(store, :account_trie_nodes, hash)
                Store.delete(store, :storage_trie_nodes, hash)
              end)

              :ets.delete(refs_table, block_num)
              :ets.delete(roots_table, block_num)
              acc + length(prunable)

            [] ->
              :ets.delete(roots_table, block_num)
              acc
          end
        end)

      if pruned > 0 do
        Logger.info("Pruned #{pruned} trie nodes from #{length(old_blocks)} old blocks")
      end

      {pruned,
       %{
         state
         | pruned_count: total_pruned + pruned,
           last_pruned_at: DateTime.utc_now()
       }}
    end
  end

  @spec collect_old_blocks(:ets.table(), non_neg_integer()) :: [non_neg_integer()]
  defp collect_old_blocks(roots_table, cutoff) do
    :ets.select(roots_table, [
      {{:"$1", :_}, [{:<, :"$1", cutoff}], [:"$1"]}
    ])
  end

  @spec collect_retained_nodes(:ets.table(), non_neg_integer()) :: MapSet.t()
  defp collect_retained_nodes(refs_table, cutoff) do
    :ets.foldl(
      fn
        {block_num, node_set}, acc when block_num >= cutoff ->
          MapSet.union(acc, node_set)

        _entry, acc ->
          acc
      end,
      MapSet.new(),
      refs_table
    )
  end

  @spec schedule_prune(non_neg_integer()) :: reference()
  defp schedule_prune(interval) do
    Process.send_after(self(), :auto_prune, interval)
  end
end
