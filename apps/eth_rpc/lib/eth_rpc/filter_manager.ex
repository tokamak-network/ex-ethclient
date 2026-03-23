defmodule EthRpc.FilterManager do
  @moduledoc """
  GenServer that manages event filters for JSON-RPC subscriptions.

  Supports log filters, block filters, and pending transaction filters.
  Each filter has a unique hex ID and tracks changes since last poll.
  """

  use GenServer

  @type filter_id :: String.t()
  @type filter_spec ::
          {:log, map()}
          | {:block, non_neg_integer()}
          | {:pending_tx, non_neg_integer()}

  @type state :: %{
          next_id: non_neg_integer(),
          filters: %{filter_id() => filter_spec()},
          changes: %{filter_id() => [term()]}
        }

  # --- Public API ---

  @doc "Starts the FilterManager GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Creates a new log filter with the given parameters."
  @spec new_filter(GenServer.server(), map()) :: {:ok, filter_id()}
  def new_filter(server \\ __MODULE__, filter_params) do
    GenServer.call(server, {:new_filter, :log, filter_params})
  end

  @doc "Creates a new block filter that tracks new block hashes."
  @spec new_block_filter(GenServer.server()) :: {:ok, filter_id()}
  def new_block_filter(server \\ __MODULE__) do
    GenServer.call(server, {:new_filter, :block, %{}})
  end

  @doc "Creates a new pending transaction filter."
  @spec new_pending_tx_filter(GenServer.server()) :: {:ok, filter_id()}
  def new_pending_tx_filter(server \\ __MODULE__) do
    GenServer.call(server, {:new_filter, :pending_tx, %{}})
  end

  @doc "Returns new items since last poll for the given filter."
  @spec get_filter_changes(GenServer.server(), filter_id()) ::
          {:ok, [term()]} | {:error, :not_found}
  def get_filter_changes(server \\ __MODULE__, filter_id) do
    GenServer.call(server, {:get_filter_changes, filter_id})
  end

  @doc "Returns all logs matching a log filter's criteria."
  @spec get_filter_logs(GenServer.server(), filter_id()) ::
          {:ok, [term()]} | {:error, :not_found}
  def get_filter_logs(server \\ __MODULE__, filter_id) do
    GenServer.call(server, {:get_filter_logs, filter_id})
  end

  @doc "Removes a filter. Returns true if the filter existed."
  @spec uninstall_filter(GenServer.server(), filter_id()) :: boolean()
  def uninstall_filter(server \\ __MODULE__, filter_id) do
    GenServer.call(server, {:uninstall_filter, filter_id})
  end

  @doc "Adds a change item to a filter's pending changes."
  @spec add_change(GenServer.server(), filter_id(), term()) :: :ok
  def add_change(server \\ __MODULE__, filter_id, item) do
    GenServer.cast(server, {:add_change, filter_id, item})
  end

  @doc "Adds a block hash change to all block filters."
  @spec notify_new_block(GenServer.server(), binary()) :: :ok
  def notify_new_block(server \\ __MODULE__, block_hash) do
    GenServer.cast(server, {:notify_new_block, block_hash})
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(_opts) do
    {:ok, %{next_id: 1, filters: %{}, changes: %{}}}
  end

  @impl true
  def handle_call({:new_filter, :log, params}, _from, state) do
    {filter_id, state} = allocate_filter(state, {:log, params})
    {:reply, {:ok, filter_id}, state}
  end

  @impl true
  def handle_call({:new_filter, :block, _params}, _from, state) do
    {filter_id, state} = allocate_filter(state, {:block, 0})
    {:reply, {:ok, filter_id}, state}
  end

  @impl true
  def handle_call({:new_filter, :pending_tx, _params}, _from, state) do
    {filter_id, state} = allocate_filter(state, {:pending_tx, 0})
    {:reply, {:ok, filter_id}, state}
  end

  @impl true
  def handle_call({:get_filter_changes, filter_id}, _from, state) do
    if Map.has_key?(state.filters, filter_id) do
      changes = Map.get(state.changes, filter_id, [])
      new_state = put_in(state.changes[filter_id], [])
      {:reply, {:ok, changes}, new_state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_filter_logs, filter_id}, _from, state) do
    case Map.fetch(state.filters, filter_id) do
      {:ok, {:log, _params}} ->
        # Return accumulated log changes (full query would need store access)
        changes = Map.get(state.changes, filter_id, [])
        {:reply, {:ok, changes}, state}

      {:ok, _other} ->
        {:reply, {:error, :not_found}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:uninstall_filter, filter_id}, _from, state) do
    if Map.has_key?(state.filters, filter_id) do
      new_state = %{
        state
        | filters: Map.delete(state.filters, filter_id),
          changes: Map.delete(state.changes, filter_id)
      }

      {:reply, true, new_state}
    else
      {:reply, false, state}
    end
  end

  @impl true
  def handle_cast({:add_change, filter_id, item}, state) do
    if Map.has_key?(state.filters, filter_id) do
      changes = Map.get(state.changes, filter_id, [])
      new_state = put_in(state.changes[filter_id], changes ++ [item])
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:notify_new_block, block_hash}, state) do
    new_changes =
      Enum.reduce(state.filters, state.changes, fn
        {fid, {:block, _}}, acc ->
          existing = Map.get(acc, fid, [])
          Map.put(acc, fid, existing ++ [block_hash])

        _other, acc ->
          acc
      end)

    {:noreply, %{state | changes: new_changes}}
  end

  # --- Private ---

  @spec allocate_filter(state(), filter_spec()) :: {filter_id(), state()}
  defp allocate_filter(state, spec) do
    id = encode_filter_id(state.next_id)

    new_state = %{
      state
      | next_id: state.next_id + 1,
        filters: Map.put(state.filters, id, spec),
        changes: Map.put(state.changes, id, [])
    }

    {id, new_state}
  end

  @spec encode_filter_id(non_neg_integer()) :: String.t()
  defp encode_filter_id(n) do
    "0x" <> Integer.to_string(n, 16) |> String.downcase()
  end
end
