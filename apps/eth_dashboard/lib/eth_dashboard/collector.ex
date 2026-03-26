defmodule EthDashboard.Collector do
  @moduledoc """
  Gathers metrics from other apps every second.

  Provides a report API for other modules to push events:
  - `report_engine/2` — Engine API method call + status
  - `report_block/4` — newly stored block info
  - `report_message/1` — network message sent/received

  All cross-app calls in the tick use try/catch so the dashboard
  works even when the networking or chain apps are not running.
  """

  use GenServer

  @tick 1_000

  defstruct peers: [],
            peer_count: 0,
            sync_status: "idle",
            current_block: 0,
            target_block: 0,
            blocks_per_sec: 0.0,
            prev_block: 0,
            prev_tick: nil,
            engine_requests: [],
            latest_blocks: [],
            messages_sent: 0,
            messages_received: 0,
            memory_mb: 0.0,
            process_count: 0,
            uptime_seconds: 0,
            started_at: nil,
            beacon_fetcher: nil

  # --- Public API ---

  @doc "Starts the Collector GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc "Returns the current collector state."
  @spec get_state() :: %__MODULE__{}
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @doc "Reports an Engine API call (e.g., newPayload, forkchoiceUpdated) and its status."
  @spec report_engine(String.t(), String.t()) :: :ok
  def report_engine(method, status) do
    GenServer.cast(__MODULE__, {:engine, method, status})
  end

  @doc "Reports a newly processed block."
  @spec report_block(non_neg_integer(), binary(), non_neg_integer(), non_neg_integer()) :: :ok
  def report_block(number, hash, tx_count, gas_used) do
    GenServer.cast(__MODULE__, {:block, number, hash, tx_count, gas_used})
  end

  @doc "Reports a network message sent or received."
  @spec report_message(:sent | :received) :: :ok
  def report_message(direction) do
    GenServer.cast(__MODULE__, {:msg, direction})
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    Process.send_after(self(), :tick, @tick)
    {:ok, %__MODULE__{started_at: System.monotonic_time(:second)}}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast({:engine, method, status}, state) do
    ts = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")
    entry = %{method: method, status: status, time: ts}
    requests = [entry | state.engine_requests] |> Enum.take(20)
    {:noreply, %{state | engine_requests: requests}}
  end

  def handle_cast({:block, number, hash, tx_count, gas_used}, state) do
    hash_hex =
      if is_binary(hash) and byte_size(hash) > 0 do
        Base.encode16(hash, case: :lower)
      else
        ""
      end

    entry = %{
      number: number,
      hash: String.slice(hash_hex, 0, 16),
      tx_count: tx_count,
      gas_used: gas_used
    }

    blocks = [entry | state.latest_blocks] |> Enum.take(10)
    current = max(state.current_block, number)
    {:noreply, %{state | latest_blocks: blocks, current_block: current}}
  end

  def handle_cast({:msg, :sent}, state) do
    {:noreply, %{state | messages_sent: state.messages_sent + 1}}
  end

  def handle_cast({:msg, :received}, state) do
    {:noreply, %{state | messages_received: state.messages_received + 1}}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.monotonic_time(:second)

    # Collect from other apps (safe — returns defaults if apps not running)
    {peer_count, peers} = collect_peers()
    {sync_status, sync_current, sync_target} = collect_sync()

    # Calculate blocks/sec
    elapsed = if state.prev_tick, do: max(now - state.prev_tick, 1), else: 1
    current = max(state.current_block, sync_current)

    bps =
      if elapsed > 0,
        do: Float.round((current - state.prev_block) / elapsed, 1),
        else: 0.0

    beacon_status = collect_beacon_fetcher()

    state = %{
      state
      | peer_count: peer_count,
        peers: peers,
        sync_status: sync_status,
        current_block: current,
        target_block: sync_target,
        blocks_per_sec: bps,
        prev_block: current,
        prev_tick: now,
        memory_mb: Float.round(:erlang.memory(:total) / 1_048_576, 1),
        process_count: :erlang.system_info(:process_count),
        uptime_seconds: now - (state.started_at || now),
        beacon_fetcher: beacon_status
    }

    Process.send_after(self(), :tick, @tick)
    {:noreply, state}
  end

  # --- Private helpers ---

  @spec collect_peers() :: {non_neg_integer(), [map()]}
  defp collect_peers do
    count = EthNet.Peer.Manager.connected_count()

    peers =
      EthNet.Peer.Manager.connected_peers()
      |> Enum.map(fn p ->
        %{
          ip: format_ip(p[:remote_ip]),
          port: p[:remote_port],
          client:
            to_string(p[:client_id] || get_in(p, [:remote_hello, :client_id]) || "unknown")
            |> String.slice(0, 40),
          state: to_string(p[:state] || "connected")
        }
      end)

    {count, peers}
  catch
    _, _ -> {0, []}
  end

  @spec collect_sync() :: {String.t(), non_neg_integer(), non_neg_integer()}
  defp collect_sync do
    # Get actual stored block number from storage
    stored_block = get_stored_block_number()
    beacon = collect_beacon_fetcher()

    cond do
      beacon && beacon[:syncing] ->
        # last_block_number = actually synced block, stored_block = network head from forkchoice
        current = beacon[:last_block_number] || 0
        target = max(stored_block, current)
        {"syncing", current, target}

      beacon && stored_block > 0 ->
        target = max(beacon[:last_block_number] || stored_block, stored_block)
        {"synced", stored_block, target}

      true ->
        s = EthNet.Sync.Manager.status()
        {to_string(s[:status] || "idle"), stored_block, s[:target_block] || 0}
    end
  catch
    _, _ -> {"idle", 0, 0}
  end

  defp get_stored_block_number do
    EthStorage.Store.get_latest_block_number(EthStorage.Store)
    |> case do
      {:ok, nil} -> 0
      {:ok, n} when is_integer(n) -> n
      _ -> 0
    end
  catch
    _, _ -> 0
  end

  @spec collect_beacon_fetcher() :: map() | nil
  defp collect_beacon_fetcher do
    if Process.whereis(EthChain.BeaconFetcher) do
      EthChain.BeaconFetcher.status()
    else
      nil
    end
  catch
    _, _ -> nil
  end

  @spec format_ip(term()) :: String.t()
  defp format_ip(nil), do: "unknown"
  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp format_ip(ip), do: to_string(ip)
end
