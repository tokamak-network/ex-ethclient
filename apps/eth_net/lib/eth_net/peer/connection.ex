defmodule EthNet.Peer.Connection do
  @moduledoc """
  Manages a single TCP connection to a remote peer.

  Lifecycle: TCP connect → RLPx handshake → Hello exchange → Status exchange → active.
  """

  use GenServer, restart: :temporary

  require Logger

  alias EthNet.RLPx.{Handshake, FrameCodec}
  alias EthNet.Protocol.{P2P, Eth68}

  @connect_timeout 5_000
  @handshake_timeout 10_000

  @hello_code P2P.hello_code()
  @disconnect_code P2P.disconnect_code()
  @ping_code P2P.ping_code()
  @status_code Eth68.status_code()

  defstruct [
    :socket,
    :remote_ip,
    :remote_port,
    :remote_node_id,
    :codec,
    :remote_hello,
    :remote_status,
    state: :connecting,
    buffer: <<>>
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns the connection state."
  def info(pid), do: GenServer.call(pid, :info)

  # --- Server callbacks ---

  @impl true
  def init(opts) do
    remote_ip = Keyword.fetch!(opts, :ip)
    remote_port = Keyword.fetch!(opts, :port)
    remote_node_id = Keyword.fetch!(opts, :node_id)

    state = %__MODULE__{
      remote_ip: remote_ip,
      remote_port: remote_port,
      remote_node_id: remote_node_id
    }

    # Start connection asynchronously
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    ip_str = :inet.ntoa(state.remote_ip)

    Logger.info("Peer: Connecting to #{ip_str}:#{state.remote_port}")

    case :gen_tcp.connect(
           state.remote_ip,
           state.remote_port,
           [
             :binary,
             active: false,
             packet: :raw,
             nodelay: true
           ],
           @connect_timeout
         ) do
      {:ok, socket} ->
        Logger.info("Peer: TCP connected to #{ip_str}:#{state.remote_port}")
        state = %{state | socket: socket, state: :handshaking}
        send(self(), :handshake)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning(
          "Peer: TCP connect failed to #{ip_str}:#{state.remote_port}: #{inspect(reason)}"
        )

        {:stop, {:connect_failed, reason}, state}
    end
  end

  def handle_info(:handshake, state) do
    case do_handshake(state) do
      {:ok, state} ->
        Logger.info(
          "Peer: RLPx handshake complete with #{:inet.ntoa(state.remote_ip)}:#{state.remote_port}"
        )

        state = %{state | state: :hello}
        send(self(), :send_hello)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Peer: Handshake failed: #{inspect(reason)}")
        {:stop, {:handshake_failed, reason}, state}
    end
  end

  def handle_info(:send_hello, state) do
    node_id = EthNet.NodeKey.node_id()
    {msg_code, payload} = P2P.encode_hello(node_id)

    case send_frame(state, msg_code, payload) do
      {:ok, state} ->
        # Read Hello response
        case recv_frame(state) do
          {:ok, code, payload, state} when code == @hello_code ->
            {:hello, hello_msg} = P2P.decode(code, payload)
            Logger.info("Peer: Hello from #{hello_msg.client_id} (v#{hello_msg.version})")

            # Check for eth/68 capability
            has_eth68? =
              Enum.any?(hello_msg.capabilities, fn {name, ver} ->
                name == "eth" and ver >= 68
              end)

            if has_eth68? do
              # Enable Snappy after Hello exchange (protocol version >= 5)
              codec =
                if hello_msg.version >= 5,
                  do: FrameCodec.enable_snappy(state.codec),
                  else: state.codec

              state = %{state | remote_hello: hello_msg, state: :status, codec: codec}
              send(self(), :send_status)
              {:noreply, state}
            else
              Logger.warning("Peer: No eth/68 capability, disconnecting")
              send_disconnect(state, :useless_peer)
              {:stop, :no_eth68, state}
            end

          {:ok, code, payload, state} when code == @disconnect_code ->
            {:disconnect, reason} = P2P.decode(code, payload)
            Logger.warning("Peer: Received Disconnect: #{inspect(reason)}")
            {:stop, {:disconnected, reason}, state}

          {:error, reason} ->
            Logger.warning("Peer: Failed to receive Hello: #{inspect(reason)}")
            {:stop, {:hello_failed, reason}, state}
        end

      {:error, reason} ->
        {:stop, {:send_hello_failed, reason}, state}
    end
  end

  def handle_info(:send_status, state) do
    {msg_code, payload} = Eth68.build_mainnet_status()

    case send_frame(state, msg_code, payload) do
      {:ok, state} ->
        case recv_frame(state) do
          {:ok, code, payload, state} when code == @status_code ->
            {:ok, status} = Eth68.decode_status(payload)

            Logger.info(
              "Peer: eth/68 Status exchanged — remote head: 0x#{Base.encode16(status.best_hash, case: :lower) |> String.slice(0, 16)}..."
            )

            Logger.info(
              "Peer: Remote network_id=#{status.network_id}, TD=#{status.total_difficulty}"
            )

            state = %{state | remote_status: status, state: :active}

            # Notify the peer manager
            send(EthNet.Peer.Manager, {:peer_connected, self(), state.remote_node_id, status})

            # Switch to active mode for incoming messages
            :inet.setopts(state.socket, active: :once)
            {:noreply, state}

          {:ok, code, payload, state} when code == @disconnect_code ->
            {:disconnect, reason} = P2P.decode(code, payload)
            Logger.warning("Peer: Received Disconnect during Status: #{inspect(reason)}")
            {:stop, {:disconnected, reason}, state}

          {:ok, code, _payload, state} ->
            # Might receive Ping before Status
            if code == @ping_code do
              state = send_pong(state)
              send(self(), :send_status)
              {:noreply, %{state | state: :status}}
            else
              Logger.warning("Peer: Unexpected message #{code} during Status exchange")
              {:stop, :unexpected_message, state}
            end

          {:error, reason} ->
            Logger.warning("Peer: Failed to receive Status: #{inspect(reason)}")
            {:stop, {:status_failed, reason}, state}
        end

      {:error, reason} ->
        {:stop, {:send_status_failed, reason}, state}
    end
  end

  @doc false
  @impl true
  def handle_info({:send_eth_message, code, payload}, state) do
    case state.codec do
      nil ->
        Logger.warning("Cannot send eth message: no codec established")
        {:noreply, state}

      _codec ->
        case send_frame(state, code, payload) do
          {:ok, state} ->
            {:noreply, state}

          {:error, reason} ->
            Logger.warning("Failed to send eth message: #{inspect(reason)}")
            {:noreply, state}
        end
    end
  end

  # Active mode: handle incoming TCP data
  def handle_info({:tcp, _socket, data}, %{state: :active} = state) do
    state = %{state | buffer: state.buffer <> data}

    case handle_active_data(state) do
      {:ok, state} ->
        :inet.setopts(state.socket, active: :once)
        {:noreply, state}

      {:stop, reason, state} ->
        {:stop, reason, state}
    end
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Peer: Connection closed by #{:inet.ntoa(state.remote_ip)}:#{state.remote_port}")
    {:stop, :tcp_closed, state}
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    Logger.warning("Peer: TCP error: #{inspect(reason)}")
    {:stop, {:tcp_error, reason}, state}
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      remote_ip: state.remote_ip,
      remote_port: state.remote_port,
      state: state.state,
      remote_hello: state.remote_hello,
      remote_status: state.remote_status
    }

    {:reply, info, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    send(EthNet.Peer.Manager, {:peer_disconnected, self()})
    :ok
  end

  # --- Private helpers ---

  defp do_handshake(state) do
    private_key = EthNet.NodeKey.private_key()
    public_key = EthNet.NodeKey.public_key()

    hs = Handshake.initiator(private_key, public_key, state.remote_node_id)

    with {:ok, auth_msg, hs} <- Handshake.build_auth(hs),
         :ok <- tcp_send(state.socket, auth_msg),
         {:ok, ack_data} <- tcp_recv_ack(state.socket),
         {:ok, hs} <- Handshake.read_ack(ack_data, hs),
         {:ok, secrets} <- Handshake.derive_secrets(hs) do
      codec = FrameCodec.init(secrets)
      {:ok, %{state | codec: codec}}
    end
  end

  defp tcp_send(socket, data) do
    :gen_tcp.send(socket, data)
  end

  defp tcp_recv_ack(socket) do
    # Read 2-byte size prefix
    case :gen_tcp.recv(socket, 2, @handshake_timeout) do
      {:ok, <<size::big-unsigned-16>>} ->
        case :gen_tcp.recv(socket, size, @handshake_timeout) do
          {:ok, data} ->
            {:ok, <<size::big-unsigned-16, data::binary>>}

          {:error, reason} ->
            {:error, {:ack_recv_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:ack_size_recv_failed, reason}}
    end
  end

  defp send_frame(state, msg_code, payload) do
    {:ok, frame, codec} = FrameCodec.encode(state.codec, msg_code, payload)

    case :gen_tcp.send(state.socket, frame) do
      :ok -> {:ok, %{state | codec: codec}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp recv_frame(state) do
    # Read enough data for a frame (header + header-mac = 32 bytes minimum)
    case recv_until_frame(state.socket, state.buffer, state.codec) do
      {:ok, msg_code, payload, remaining, codec} ->
        {:ok, msg_code, payload, %{state | codec: codec, buffer: remaining}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_until_frame(socket, buffer, codec) do
    case FrameCodec.decode(codec, buffer) do
      {:ok, msg_code, payload, remaining, codec} ->
        {:ok, msg_code, payload, remaining, codec}

      {:error, :insufficient_data} ->
        recv_more_and_retry(socket, buffer, codec)

      {:error, :incomplete_frame} ->
        recv_more_and_retry(socket, buffer, codec)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_more_and_retry(socket, buffer, codec) do
    case :gen_tcp.recv(socket, 0, @handshake_timeout) do
      {:ok, data} ->
        recv_until_frame(socket, buffer <> data, codec)

      {:error, reason} ->
        {:error, {:tcp_recv_failed, reason}}
    end
  end

  defp handle_active_data(state) do
    case FrameCodec.decode(state.codec, state.buffer) do
      {:ok, msg_code, payload, remaining, codec} ->
        state = %{state | codec: codec, buffer: remaining}
        handle_message(msg_code, payload, state)

      {:error, :insufficient_data} ->
        {:ok, state}

      {:error, :incomplete_frame} ->
        {:ok, state}

      {:error, reason} ->
        {:stop, {:decode_error, reason}, state}
    end
  end

  defp handle_message(code, payload, state) do
    cond do
      code == @ping_code ->
        state = send_pong(state)
        {:ok, state}

      code == P2P.pong_code() ->
        {:ok, state}

      code == @disconnect_code ->
        {:disconnect, reason} = P2P.decode(code, payload)
        Logger.info("Peer: Disconnect from #{:inet.ntoa(state.remote_ip)}: #{inspect(reason)}")
        {:stop, {:disconnected, reason}, state}

      Eth68.eth_message?(code) ->
        handle_eth_message(code, payload, state)

      true ->
        Logger.debug("Peer: Received message code=#{code} (#{byte_size(payload)} bytes)")
        {:ok, state}
    end
  end

  defp handle_eth_message(code, payload, state) do
    case Eth68.decode(code, payload) do
      {:ok, {msg_type, msg}} ->
        dispatch_eth_message(msg_type, msg, state)

      {:error, reason} ->
        Logger.warning("Peer: Failed to decode eth msg code=#{code}: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp dispatch_eth_message(:get_block_headers, msg, state) do
    Logger.debug("Peer: GetBlockHeaders req=#{msg.request_id}")
    # Respond with empty headers (we don't have blocks yet)
    {resp_code, resp_payload} = Eth68.encode_block_headers(msg.request_id, [])

    case send_frame(state, resp_code, resp_payload) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} -> {:ok, state}
    end
  end

  defp dispatch_eth_message(:block_headers, msg, state) do
    Logger.debug("Peer: BlockHeaders req=#{msg.request_id}, count=#{length(msg.headers)}")
    forward_to_sync(:handle_headers, [self(), msg.request_id, msg.headers])
    {:ok, state}
  end

  defp dispatch_eth_message(:get_block_bodies, msg, state) do
    Logger.debug("Peer: GetBlockBodies req=#{msg.request_id}")
    # Respond with empty bodies (we don't have blocks yet)
    {resp_code, resp_payload} = Eth68.encode_block_bodies(msg.request_id, [])

    case send_frame(state, resp_code, resp_payload) do
      {:ok, state} -> {:ok, state}
      {:error, _reason} -> {:ok, state}
    end
  end

  defp dispatch_eth_message(:block_bodies, msg, state) do
    Logger.debug("Peer: BlockBodies req=#{msg.request_id}, count=#{length(msg.bodies)}")
    forward_to_sync(:handle_bodies, [self(), msg.request_id, msg.bodies])
    {:ok, state}
  end

  defp dispatch_eth_message(:new_block_hashes, msg, state) do
    Logger.debug("Peer: NewBlockHashes count=#{length(msg)}")
    forward_to_sync(:handle_new_block_hashes, [self(), msg])
    {:ok, state}
  end

  defp dispatch_eth_message(:new_block, msg, state) do
    Logger.debug("Peer: NewBlock TD=#{msg.total_difficulty}")
    forward_to_sync(:handle_new_block, [self(), msg])
    {:ok, state}
  end

  defp dispatch_eth_message(:transactions, _msg, state) do
    Logger.debug("Peer: Transactions received (no mempool integration yet)")
    {:ok, state}
  end

  defp dispatch_eth_message(:new_pooled_tx_hashes, msg, state) do
    Logger.debug("Peer: NewPooledTransactionHashes count=#{length(msg)}")
    {:ok, state}
  end

  defp dispatch_eth_message(msg_type, _msg, state) do
    Logger.debug("Peer: Unhandled eth message: #{msg_type}")
    {:ok, state}
  end

  defp forward_to_sync(function, args) do
    try do
      apply(EthNet.Sync.Manager, function, args)
    rescue
      _ -> :ok
    end
  end

  defp send_pong(state) do
    {code, payload} = P2P.encode_pong()

    case send_frame(state, code, payload) do
      {:ok, state} -> state
      _ -> state
    end
  end

  defp send_disconnect(state, reason) do
    {code, payload} = P2P.encode_disconnect(reason)
    send_frame(state, code, payload)
  end
end
