defmodule EthNet.Peer.Manager do
  @moduledoc """
  Manages peer connections. Listens for discovered peers from DiscV4
  and initiates TCP connections up to the maximum peer count.

  Tracks recently failed peers to avoid reconnecting too quickly.
  On peer disconnect, immediately attempts new connections instead of
  waiting for the periodic timer.
  """

  use GenServer

  require Logger

  alias EthNet.Peer.ConnectionSupervisor

  @max_peers 25
  @connect_interval 10_000
  @retry_interval 2_000
  @max_concurrent_attempts 5
  @fail_cooldown_ms 60_000

  defstruct connected: %{},
            connecting: MapSet.new(),
            max_peers: @max_peers,
            failed_peers: %{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the number of connected peers."
  def connected_count, do: GenServer.call(__MODULE__, :connected_count)

  @doc "Returns info about all connected peers."
  def connected_peers, do: GenServer.call(__MODULE__, :connected_peers)

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    max_peers = Keyword.get(opts, :max_peers, @max_peers)
    Process.send_after(self(), :try_connect, @connect_interval)
    {:ok, %__MODULE__{max_peers: max_peers}}
  end

  @impl true
  def handle_info(:try_connect, state) do
    state = attempt_connections(state)
    Process.send_after(self(), :try_connect, @connect_interval)
    {:noreply, state}
  end

  def handle_info({:peer_connected, pid, node_id, status}, state) do
    Logger.info("PeerManager: Peer connected (#{ConnectionSupervisor.count()} active)")
    ref = Process.monitor(pid)
    connected = Map.put(state.connected, pid, %{ref: ref, node_id: node_id, status: status})
    connecting = MapSet.delete(state.connecting, node_id)
    {:noreply, %{state | connected: connected, connecting: connecting}}
  end

  def handle_info({:peer_disconnected, pid}, state) do
    {node_id, state} =
      case Map.get(state.connected, pid) do
        %{ref: ref, node_id: nid} ->
          Process.demonitor(ref, [:flush])
          {nid, state}

        nil ->
          {nil, state}
      end

    connected = Map.delete(state.connected, pid)

    # Track the failed peer to avoid reconnecting too quickly
    failed_peers =
      if node_id do
        Map.put(state.failed_peers, node_id, System.monotonic_time(:millisecond))
      else
        state.failed_peers
      end

    Logger.info("PeerManager: Peer disconnected (#{map_size(connected)} active)")

    state = %{state | connected: connected, failed_peers: failed_peers}

    # Immediately try to connect to new peers instead of waiting
    Process.send_after(self(), :retry_connect, @retry_interval)

    {:noreply, state}
  end

  def handle_info(:retry_connect, state) do
    state = attempt_connections(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    connected = Map.delete(state.connected, pid)

    # Trigger reconnect on crash too
    if map_size(connected) < state.max_peers do
      Process.send_after(self(), :retry_connect, @retry_interval)
    end

    {:noreply, %{state | connected: connected}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:connected_count, _from, state) do
    {:reply, map_size(state.connected), state}
  end

  def handle_call(:connected_peers, _from, state) do
    peers =
      Enum.map(state.connected, fn {pid, info} ->
        try do
          conn_info = EthNet.Peer.Connection.info(pid)
          Map.merge(conn_info, %{node_id: info.node_id})
        rescue
          _ -> %{node_id: info.node_id, state: :unknown}
        end
      end)

    {:reply, peers, state}
  end

  # --- Private ---

  defp attempt_connections(state) do
    available_slots = state.max_peers - map_size(state.connected) - MapSet.size(state.connecting)
    # Allow more concurrent attempts to find working peers faster
    attempt_count = min(available_slots, @max_concurrent_attempts)

    if attempt_count <= 0 do
      state
    else
      # Clean up expired failed peer entries
      now = System.monotonic_time(:millisecond)

      failed_peers =
        state.failed_peers
        |> Enum.reject(fn {_id, ts} -> now - ts > @fail_cooldown_ms end)
        |> Map.new()

      state = %{state | failed_peers: failed_peers}

      # Get discovered peers from DiscV4
      discovered =
        try do
          EthNet.DiscV4.Server.peers()
        rescue
          _ -> []
        end

      # Filter out already connected/connecting/recently-failed peers
      connected_ids = MapSet.new(state.connected, fn {_pid, info} -> info.node_id end)
      failed_ids = MapSet.new(Map.keys(failed_peers))

      candidates =
        discovered
        |> Enum.reject(fn node ->
          MapSet.member?(connected_ids, node.id) or
            MapSet.member?(state.connecting, node.id) or
            MapSet.member?(failed_ids, node.id)
        end)
        |> Enum.shuffle()
        |> Enum.take(attempt_count)

      Enum.reduce(candidates, state, fn node, acc ->
        Logger.info(
          "PeerManager: Attempting connection to #{:inet.ntoa(node.ip)}:#{node.tcp_port || node.udp_port}"
        )

        case ConnectionSupervisor.start_connection(
               ip: node.ip,
               port: node.tcp_port || node.udp_port,
               node_id: node.id
             ) do
          {:ok, _pid} ->
            %{acc | connecting: MapSet.put(acc.connecting, node.id)}

          {:error, reason} ->
            Logger.warning("PeerManager: Failed to start connection: #{inspect(reason)}")
            acc
        end
      end)
    end
  end
end
