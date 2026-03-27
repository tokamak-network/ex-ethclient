defmodule EthNet.DiscV5.Server do
  @moduledoc """
  DiscV5 UDP server for peer discovery (EIP-778, Node Discovery Protocol v5).

  Listens on UDP for DiscV5 messages, manages per-peer sessions with
  WHOAREYOU/handshake flows, maintains the local ENR, and runs periodic
  FINDNODE lookups for peer discovery.

  Key differences from DiscV4:
  - Session-based encryption (AES-128-GCM) with per-peer keys
  - WHOAREYOU challenge/response handshake before message exchange
  - ENR (Ethereum Node Records) instead of simple node endpoint info
  - Masking header with AES-CTR using destination node ID
  """

  use GenServer

  require Logger

  alias EthNet.DiscV5.{ENR, Packet, Session}
  alias EthNet.DiscV4.{Node, RoutingTable}

  @lookup_interval 30_000

  @type t :: %__MODULE__{
          socket: :gen_udp.socket() | nil,
          port: :inet.port_number(),
          private_key: <<_::256>>,
          node_id: <<_::256>>,
          public_key: <<_::512>>,
          enr: ENR.t() | nil,
          enr_seq: non_neg_integer(),
          table: RoutingTable.t(),
          sessions: %{binary() => Session.t()},
          pending_challenges: %{binary() => Session.challenge()},
          pending_requests: %{non_neg_integer() => map()},
          next_request_id: non_neg_integer()
        }

  defstruct [
    :socket,
    :port,
    :private_key,
    :node_id,
    :public_key,
    :enr,
    enr_seq: 1,
    table: nil,
    sessions: %{},
    pending_challenges: %{},
    pending_requests: %{},
    next_request_id: 1
  ]

  @doc "Starts the DiscV5 server."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of known peers from the routing table."
  @spec peers() :: [Node.t()]
  def peers, do: GenServer.call(__MODULE__, :peers)

  @doc "Returns the current ENR record."
  @spec local_enr() :: ENR.t() | nil
  def local_enr, do: GenServer.call(__MODULE__, :local_enr)

  @doc "Returns the routing table size."
  @spec table_size() :: non_neg_integer()
  def table_size, do: GenServer.call(__MODULE__, :table_size)

  @doc "Initiates a lookup for nodes near the given target."
  @spec lookup(<<_::256>>) :: :ok
  def lookup(target), do: GenServer.cast(__MODULE__, {:lookup, target})

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 30304)
    bootnodes = Keyword.get(opts, :bootnodes, [])

    private_key = EthNet.NodeKey.private_key()
    public_key = EthNet.NodeKey.public_key()
    node_id = EthCrypto.Hash.keccak256(compress_public_key(public_key))

    ip = {0, 0, 0, 0}

    case :gen_udp.open(port, [:binary, active: true, reuseaddr: true]) do
      {:ok, socket} ->
        Logger.info("DiscV5: Listening on UDP port #{port}")

        {:ok, enr} = ENR.new(1, ip, port, port, private_key)

        state = %__MODULE__{
          socket: socket,
          port: port,
          private_key: private_key,
          public_key: public_key,
          node_id: node_id,
          enr: enr,
          enr_seq: 1,
          table: RoutingTable.new(public_key)
        }

        if bootnodes != [] do
          send(self(), {:bootstrap, bootnodes})
        end

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
              "DiscV5: Sending PING to bootnode #{:inet.ntoa(node.ip)}:#{node.udp_port}"
            )

            send_ping(acc, node)

          {:error, reason} ->
            Logger.warning(
              "DiscV5: Failed to parse bootnode #{enode_url}: #{inspect(reason)}"
            )

            acc
        end
      end)

    {:noreply, state}
  end

  def handle_info(:lookup, state) do
    target = :crypto.strong_rand_bytes(32)
    closest = RoutingTable.closest(state.table, target, 3)

    state =
      Enum.reduce(closest, state, fn node, acc ->
        send_findnode_to_peer(acc, node, [255, 254, 253])
      end)

    Process.send_after(self(), :lookup, @lookup_interval)
    {:noreply, state}
  end

  def handle_info({:udp, _socket, from_ip, from_port, data}, state) do
    state =
      try do
        handle_incoming_packet(data, from_ip, from_port, state)
      rescue
        e ->
          Logger.warning(
            "DiscV5: Error processing packet from #{:inet.ntoa(from_ip)}:#{from_port}: " <>
              Exception.message(e)
          )

          state
      end

    {:noreply, state}
  end

  def handle_info({:session_timeout, peer_key}, state) do
    sessions = Map.delete(state.sessions, peer_key)
    {:noreply, %{state | sessions: sessions}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(:peers, _from, state) do
    {:reply, RoutingTable.all_nodes(state.table), state}
  end

  def handle_call(:local_enr, _from, state) do
    {:reply, state.enr, state}
  end

  def handle_call(:table_size, _from, state) do
    {:reply, RoutingTable.size(state.table), state}
  end

  @impl true
  def handle_cast({:lookup, target}, state) do
    closest = RoutingTable.closest(state.table, target, 3)

    state =
      Enum.reduce(closest, state, fn node, acc ->
        send_findnode_to_peer(acc, node, [255, 254, 253])
      end)

    {:noreply, state}
  end

  # --- Incoming packet handling ---

  defp handle_incoming_packet(data, from_ip, from_port, state) do
    case Packet.decode(data, state.node_id) do
      {:ok, {0, %{src_id: src_id, nonce: nonce, encrypted_message: enc_msg, header: header}}} ->
        handle_ordinary_message(src_id, nonce, enc_msg, header, from_ip, from_port, state)

      {:ok, {1, %{nonce: nonce, id_nonce: id_nonce, enr_seq: enr_seq}}} ->
        handle_whoareyou(nonce, id_nonce, enr_seq, from_ip, from_port, state)

      {:ok, {2, handshake_data}} ->
        handle_handshake(handshake_data, from_ip, from_port, state)

      {:error, reason} ->
        Logger.debug(
          "DiscV5: Failed to decode packet from #{:inet.ntoa(from_ip)}:#{from_port}: " <>
            inspect(reason)
        )

        state
    end
  end

  defp handle_ordinary_message(src_id, nonce, enc_msg, header, from_ip, from_port, state) do
    peer_key = {from_ip, from_port}

    case Map.get(state.sessions, peer_key) do
      nil ->
        # No session, send WHOAREYOU
        Logger.debug("DiscV5: No session for #{:inet.ntoa(from_ip)}:#{from_port}, sending WHOAREYOU")
        send_whoareyou(state, from_ip, from_port, nonce)

      session ->
        case Session.decrypt(session, enc_msg, nonce, header) do
          {:ok, plaintext} ->
            handle_decrypted_message(plaintext, src_id, from_ip, from_port, state)

          {:error, _reason} ->
            Logger.debug("DiscV5: Decryption failed, sending WHOAREYOU")
            send_whoareyou(state, from_ip, from_port, nonce)
        end
    end
  end

  defp handle_whoareyou(_nonce, id_nonce, enr_seq, from_ip, from_port, state) do
    Logger.debug("DiscV5: Received WHOAREYOU from #{:inet.ntoa(from_ip)}:#{from_port}")

    # Store the challenge for when we send the handshake response
    peer_key = {from_ip, from_port}
    challenge = %{id_nonce: id_nonce, enr_seq: enr_seq}
    pending = Map.put(state.pending_challenges, peer_key, challenge)
    %{state | pending_challenges: pending}
  end

  defp handle_handshake(data, from_ip, from_port, state) do
    %{
      src_id: src_id,
      ephemeral_pubkey: _ephemeral_pubkey,
      encrypted_message: enc_msg,
      nonce: nonce,
      header: header
    } = data

    Logger.debug("DiscV5: Received handshake from #{:inet.ntoa(from_ip)}:#{from_port}")

    # For a minimal implementation, create a session from the handshake data
    # In production, we would verify the id_signature and derive keys from ECDH
    peer_key = {from_ip, from_port}

    # Attempt to use the session if one was derived during the handshake
    case Map.get(state.sessions, peer_key) do
      nil ->
        Logger.debug("DiscV5: No session available for handshake decryption")
        state

      session ->
        case Session.decrypt(session, enc_msg, nonce, header) do
          {:ok, plaintext} ->
            handle_decrypted_message(plaintext, src_id, from_ip, from_port, state)

          {:error, _reason} ->
            Logger.debug("DiscV5: Handshake decryption failed")
            state
        end
    end
  end

  defp handle_decrypted_message(plaintext, src_id, from_ip, from_port, state) do
    case Packet.decode_message(plaintext) do
      {:ok, {:ping, msg}} ->
        handle_ping(msg, src_id, from_ip, from_port, state)

      {:ok, {:pong, msg}} ->
        handle_pong(msg, src_id, from_ip, from_port, state)

      {:ok, {:findnode, msg}} ->
        handle_findnode(msg, src_id, from_ip, from_port, state)

      {:ok, {:nodes, msg}} ->
        handle_nodes(msg, src_id, from_ip, from_port, state)

      {:ok, {type, _msg}} ->
        Logger.debug("DiscV5: Unhandled message type #{type}")
        state

      {:error, reason} ->
        Logger.debug("DiscV5: Failed to decode message: #{inspect(reason)}")
        state
    end
  end

  # --- Message handlers ---

  defp handle_ping(msg, _src_id, from_ip, from_port, state) do
    Logger.debug("DiscV5: Received PING from #{:inet.ntoa(from_ip)}:#{from_port}")

    pong_payload = Packet.encode_pong(msg.request_id, state.enr_seq, from_ip, from_port)
    send_encrypted(state, from_ip, from_port, pong_payload)
  end

  defp handle_pong(msg, src_id, from_ip, from_port, state) do
    Logger.info("DiscV5: Received PONG from #{:inet.ntoa(from_ip)}:#{from_port}")

    # Remove from pending requests
    pending = Map.delete(state.pending_requests, msg.request_id)

    # Add node to routing table (use src_id as a pseudo node ID)
    node = %Node{
      id: pad_to_64(src_id),
      ip: from_ip,
      udp_port: from_port,
      tcp_port: from_port,
      last_pong: System.system_time(:second)
    }

    table = RoutingTable.insert(state.table, node)
    %{state | table: table, pending_requests: pending}
  end

  defp handle_findnode(msg, _src_id, from_ip, from_port, state) do
    Logger.debug("DiscV5: Received FINDNODE from #{:inet.ntoa(from_ip)}:#{from_port}")

    nodes =
      Enum.flat_map(msg.distances, fn distance ->
        # Find nodes at this log distance
        all = RoutingTable.all_nodes(state.table)

        Enum.filter(all, fn node ->
          Node.log_distance(state.public_key, node.id) == distance
        end)
      end)
      |> Enum.take(16)

    # Encode ENR records for each node
    enr_records = Enum.map(nodes, fn _node -> <<>> end)
    nodes_payload = Packet.encode_nodes(msg.request_id, 1, enr_records)
    send_encrypted(state, from_ip, from_port, nodes_payload)
  end

  defp handle_nodes(msg, _src_id, from_ip, from_port, state) do
    Logger.info(
      "DiscV5: Received NODES from #{:inet.ntoa(from_ip)}:#{from_port} " <>
        "with #{length(msg.enr_records)} records"
    )

    # Decode ENR records and add to routing table
    state =
      Enum.reduce(msg.enr_records, state, fn enr_data, acc ->
        case ENR.decode(enr_data) do
          {:ok, enr} ->
            with {:ok, ip} <- ENR.ip(enr),
                 {:ok, udp} <- ENR.udp_port(enr),
                 {:ok, enr_node_id} <- ENR.node_id(enr) do
              node = %Node{
                id: pad_to_64(enr_node_id),
                ip: ip,
                udp_port: udp,
                tcp_port: udp
              }

              %{acc | table: RoutingTable.insert(acc.table, node)}
            else
              _ -> acc
            end

          _ ->
            acc
        end
      end)

    pending = Map.delete(state.pending_requests, msg.request_id)
    %{state | pending_requests: pending}
  end

  # --- Sending helpers ---

  defp send_ping(state, node) do
    {request_id, state} = next_request_id(state)
    payload = Packet.encode_ping(request_id, state.enr_seq)

    pending =
      Map.put(state.pending_requests, request_id, %{
        type: :ping,
        node: node,
        sent_at: System.system_time(:second)
      })

    state = %{state | pending_requests: pending}
    send_encrypted(state, node.ip, node.udp_port, payload)
  end

  defp send_findnode_to_peer(state, node, distances) do
    {request_id, state} = next_request_id(state)
    payload = Packet.encode_findnode(request_id, distances)

    pending =
      Map.put(state.pending_requests, request_id, %{
        type: :findnode,
        node: node,
        sent_at: System.system_time(:second)
      })

    state = %{state | pending_requests: pending}
    send_encrypted(state, node.ip, node.udp_port, payload)
  end

  defp send_whoareyou(state, ip, port, nonce) do
    challenge = Session.new_challenge(state.enr_seq)

    # Create a random dest_node_id since we don't know the sender yet
    dest_node_id = :crypto.strong_rand_bytes(32)
    packet = Packet.encode_whoareyou(dest_node_id, nonce, challenge.id_nonce, challenge.enr_seq)

    :gen_udp.send(state.socket, ip, port, packet)

    peer_key = {ip, port}
    pending = Map.put(state.pending_challenges, peer_key, challenge)
    %{state | pending_challenges: pending}
  end

  defp send_encrypted(state, ip, port, payload) do
    peer_key = {ip, port}

    case Map.get(state.sessions, peer_key) do
      nil ->
        # No session yet; send as raw packet (will trigger WHOAREYOU)
        # Wrap in a minimal ordinary message packet format
        masking_iv = :crypto.strong_rand_bytes(16)
        nonce = :crypto.strong_rand_bytes(12)
        # Dest node_id unknown, use zeros
        dest_node_id = :crypto.strong_rand_bytes(32)

        # Send unencrypted for now to trigger handshake
        static_header = "discv5" <> <<0x0001::16, 0::8>> <> nonce <> <<32::16>>
        auth_data = state.node_id
        header = static_header <> auth_data

        key = binary_part(dest_node_id, 0, 16)
        masked_header = :crypto.crypto_one_time(:aes_128_ctr, key, masking_iv, header, true)

        packet = masking_iv <> masked_header <> payload
        :gen_udp.send(state.socket, ip, port, packet)
        state

      session ->
        nonce = :crypto.strong_rand_bytes(12)
        dest_node_id = session.node_id

        case Packet.encode_message_packet(payload, dest_node_id, nonce, session) do
          {:ok, packet, updated_session} ->
            :gen_udp.send(state.socket, ip, port, packet)
            sessions = Map.put(state.sessions, peer_key, updated_session)
            %{state | sessions: sessions}

          {:error, reason} ->
            Logger.warning("DiscV5: Failed to encode packet: #{inspect(reason)}")
            state
        end
    end
  end

  defp next_request_id(%__MODULE__{next_request_id: id} = state) do
    {id, %{state | next_request_id: id + 1}}
  end

  defp pad_to_64(bin) when byte_size(bin) >= 64, do: binary_part(bin, 0, 64)

  defp pad_to_64(bin) do
    padding = 64 - byte_size(bin)
    bin <> :binary.copy(<<0>>, padding)
  end

  defp compress_public_key(<<_::binary-size(64)>> = uncompressed) do
    <<x::binary-size(32), _y::binary-size(32)>> = uncompressed
    y_int = :binary.decode_unsigned(binary_part(uncompressed, 32, 32))
    prefix = if rem(y_int, 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end
end
