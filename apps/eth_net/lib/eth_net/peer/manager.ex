defmodule EthNet.Peer.Manager do
  @moduledoc """
  Manages peer connections. Listens for discovered peers from DiscV4
  and initiates TCP connections up to the maximum peer count.
  """

  use GenServer

  require Logger

  alias EthNet.Peer.ConnectionSupervisor

  @max_peers 25
  @connect_interval 10_000

  defstruct connected: %{},
            connecting: MapSet.new(),
            max_peers: @max_peers

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
    case Map.get(state.connected, pid) do
      %{ref: ref} ->
        Process.demonitor(ref, [:flush])

      nil ->
        :ok
    end

    connected = Map.delete(state.connected, pid)
    Logger.info("PeerManager: Peer disconnected (#{map_size(connected)} active)")
    {:noreply, %{state | connected: connected}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    connected = Map.delete(state.connected, pid)
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

    if available_slots <= 0 do
      state
    else
      # Get discovered peers from DiscV4
      discovered =
        try do
          EthNet.DiscV4.Server.peers()
        rescue
          _ -> []
        end

      # Filter out already connected/connecting peers
      connected_ids = MapSet.new(state.connected, fn {_pid, info} -> info.node_id end)

      candidates =
        discovered
        |> Enum.reject(fn node ->
          MapSet.member?(connected_ids, node.id) or MapSet.member?(state.connecting, node.id)
        end)
        |> Enum.take(available_slots)

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
