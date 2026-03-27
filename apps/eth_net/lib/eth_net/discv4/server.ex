defmodule EthNet.DiscV4.Server do
  @moduledoc """
  DiscV4 UDP server for peer discovery.

  Sends PING to bootnodes, handles PONG/FINDNODE/NEIGHBOURS,
  and periodically performs random lookups to discover new peers.
  """

  use GenServer

  require Logger

  alias EthNet.DiscV4.{Node, Packet, RoutingTable}

  @lookup_interval 30_000
  @ping_timeout 5_000

  defstruct [
    :socket,
    :port,
    :private_key,
    :public_key,
    :table,
    :chain,
    pending_pings: %{}
  ]

  @doc "Starts the DiscV4 UDP discovery server."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current routing table size."
  @spec table_size() :: non_neg_integer()
  def table_size, do: GenServer.call(__MODULE__, :table_size)

  @doc "Returns known peers."
  @spec peers() :: [EthNet.DiscV4.Node.t()]
  def peers, do: GenServer.call(__MODULE__, :peers)

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 30303)
    chain = Keyword.get(opts, :chain, :mainnet)
    bootnodes = Keyword.get(opts, :bootnodes, EthNet.Chain.bootnodes(chain))

    private_key = EthNet.NodeKey.private_key()
    public_key = EthNet.NodeKey.public_key()

    case :gen_udp.open(port, [:binary, active: true, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("DiscV4: Listening on UDP port #{port}")

        state = %__MODULE__{
          socket: socket,
          port: port,
          private_key: private_key,
          public_key: public_key,
          table: RoutingTable.new(public_key),
          chain: chain
        }

        # Bootstrap: ping all bootnodes
        send(self(), {:bootstrap, bootnodes})

        # Schedule periodic lookups
        Process.send_after(self(), :lookup, @lookup_interval)

        {:ok, state}

      {:error, reason} ->
        {:stop, {:udp_open_failed, reason}}
    end
  end

  @impl true
  def handle_info({:bootstrap, bootnodes}, state) do
    state =
      Enum.reduce(bootnodes, state, fn enode_url, acc ->
        case Node.from_enode(enode_url) do
          {:ok, node} ->
            Logger.info(
              "DiscV4: Sending PING to bootnode #{:inet.ntoa(node.ip)}:#{node.udp_port}"
            )

            send_ping(acc, node.ip, node.udp_port, node.tcp_port || node.udp_port)

          {:error, reason} ->
            Logger.warning("DiscV4: Failed to parse bootnode #{enode_url}: #{inspect(reason)}")
            acc
        end
      end)

    {:noreply, state}
  end

  def handle_info(:lookup, state) do
    # Perform a random lookup to discover new peers
    target = RoutingTable.random_target()
    closest = RoutingTable.closest(state.table, target, 3)

    state =
      Enum.reduce(closest, state, fn node, acc ->
        send_findnode(acc, node, target)
      end)

    Process.send_after(self(), :lookup, @lookup_interval)
    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, from_port, data}, state) do
    state =
      try do
        case Packet.decode(data) do
          {:ok, {type, msg, node_id, hash}} ->
            handle_packet(type, msg, node_id, hash, from_ip, from_port, state)

          {:error, reason} ->
            Logger.debug(
              "DiscV4: Failed to decode packet from #{:inet.ntoa(from_ip)}:#{from_port}: #{inspect(reason)}"
            )

            state
        end
      rescue
        e ->
          Logger.warning(
            "DiscV4: Error processing packet from #{:inet.ntoa(from_ip)}:#{from_port}: #{Exception.message(e)}"
          )

          state
      end

    {:noreply, state}
  end

  def handle_info({:ping_timeout, ip_port_key}, state) do
    state = %{state | pending_pings: Map.delete(state.pending_pings, ip_port_key)}
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:table_size, _from, state) do
    {:reply, RoutingTable.size(state.table), state}
  end

  def handle_call(:peers, _from, state) do
    {:reply, RoutingTable.all_nodes(state.table), state}
  end

  # --- Packet handlers ---

  defp handle_packet(:ping, msg, node_id, hash, from_ip, from_port, state) do
    Logger.debug("DiscV4: Received PING from #{:inet.ntoa(from_ip)}:#{from_port}")

    # Respond with PONG
    tcp_port = msg.to.tcp_port
    {:ok, pong_data} = Packet.encode_pong(from_ip, from_port, tcp_port, hash, state.private_key)
    :gen_udp.send(state.socket, from_ip, from_port, pong_data)

    # Add to table
    node = %Node{
      id: node_id,
      ip: from_ip,
      udp_port: from_port,
      tcp_port: from_port,
      last_pong: now()
    }

    table = RoutingTable.insert(state.table, node)
    %{state | table: table}
  end

  defp handle_packet(:pong, msg, node_id, _hash, from_ip, from_port, state) do
    Logger.info("DiscV4: Received PONG from #{:inet.ntoa(from_ip)}:#{from_port}")

    ip_port_key = {from_ip, from_port}

    case Map.get(state.pending_pings, ip_port_key) do
      nil ->
        Logger.debug("DiscV4: Unexpected PONG (no pending ping)")
        state

      expected_hash ->
        if msg.ping_hash == expected_hash do
          node = %Node{
            id: node_id,
            ip: from_ip,
            udp_port: from_port,
            tcp_port: from_port,
            last_pong: now()
          }

          table = RoutingTable.insert(state.table, node)

          Logger.info(
            "DiscV4: Added peer #{:inet.ntoa(from_ip)}:#{from_port} (table size: #{RoutingTable.size(table)})"
          )

          state = %{
            state
            | table: table,
              pending_pings: Map.delete(state.pending_pings, ip_port_key)
          }

          # After first PONG, do a self-lookup
          send_findnode(state, node, state.public_key)
        else
          state
        end
    end
  end

  defp handle_packet(:findnode, msg, node_id, _hash, from_ip, from_port, state) do
    Logger.debug("DiscV4: Received FINDNODE from #{:inet.ntoa(from_ip)}:#{from_port}")

    closest = RoutingTable.closest(state.table, msg.target, 16)
    {:ok, data} = Packet.encode_neighbours(closest, state.private_key)
    :gen_udp.send(state.socket, from_ip, from_port, data)

    node = %Node{id: node_id, ip: from_ip, udp_port: from_port, tcp_port: from_port}
    table = RoutingTable.insert(state.table, node)
    %{state | table: table}
  end

  defp handle_packet(:neighbours, msg, _node_id, _hash, from_ip, from_port, state) do
    Logger.info(
      "DiscV4: Received NEIGHBOURS from #{:inet.ntoa(from_ip)}:#{from_port} with #{length(msg.nodes)} nodes"
    )

    Enum.reduce(msg.nodes, state, fn node, acc ->
      if node.id != acc.public_key and node.udp_port > 0 do
        send_ping(acc, node.ip, node.udp_port, node.tcp_port || node.udp_port)
      else
        acc
      end
    end)
  end

  # --- Sending helpers ---

  defp send_ping(state, ip, udp_port, tcp_port) do
    from_ip = {0, 0, 0, 0}

    {:ok, data} =
      Packet.encode_ping(
        from_ip,
        state.port,
        state.port,
        ip,
        udp_port,
        tcp_port,
        state.private_key
      )

    # Extract hash (first 32 bytes) for matching PONG
    <<ping_hash::binary-size(32), _::binary>> = data

    :gen_udp.send(state.socket, ip, udp_port, data)

    ip_port_key = {ip, udp_port}
    Process.send_after(self(), {:ping_timeout, ip_port_key}, @ping_timeout)

    %{state | pending_pings: Map.put(state.pending_pings, ip_port_key, ping_hash)}
  end

  defp send_findnode(state, node, target) do
    {:ok, data} = Packet.encode_findnode(target, state.private_key)
    :gen_udp.send(state.socket, node.ip, node.udp_port, data)
    state
  end

  defp now, do: System.system_time(:second)
end
