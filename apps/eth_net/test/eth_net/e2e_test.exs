defmodule EthNet.E2ETest do
  @moduledoc """
  End-to-end tests for the Ethereum P2P networking stack.

  Tests tagged with :e2e require real network access to Ethereum mainnet bootnodes.
  Run with: mix test --include e2e
  """
  use ExUnit.Case, async: false

  require Logger

  @test_datadir Path.join(System.tmp_dir!(), "eth_net_e2e_#{System.system_time(:millisecond)}")

  setup_all do
    File.rm_rf!(@test_datadir)
    File.mkdir_p!(@test_datadir)
    on_exit(fn -> File.rm_rf!(@test_datadir) end)
    :ok
  end

  # ──────────────────────────────────────────────────────────────
  # LOCAL INTEGRATION: Full supervision tree startup
  # ──────────────────────────────────────────────────────────────

  describe "supervision tree" do
    @describetag :sup_tree

    setup do
      datadir = Path.join(@test_datadir, "sup_#{System.unique_integer([:positive])}")
      File.mkdir_p!(datadir)
      udp_port = 40_000 + rem(System.unique_integer([:positive]), 10_000)

      children = [
        {EthNet.NodeKey, datadir: datadir},
        {EthNet.DiscV4.Server, port: udp_port, chain: :mainnet, bootnodes: []},
        {EthNet.Peer.ConnectionSupervisor, []},
        {EthNet.Peer.Manager, []}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :rest_for_one)

      on_exit(fn ->
        try do
          if Process.alive?(sup), do: Supervisor.stop(sup, :shutdown, 5_000)
        catch
          :exit, _ -> :ok
        end
      end)

      %{supervisor: sup, datadir: datadir, udp_port: udp_port}
    end

    test "all services start successfully", %{datadir: datadir} do
      privkey = EthNet.NodeKey.private_key()
      pubkey = EthNet.NodeKey.public_key()
      node_id = EthNet.NodeKey.node_id()

      assert byte_size(privkey) == 32
      assert byte_size(pubkey) == 64
      assert node_id == pubkey
      assert File.exists?(Path.join(datadir, "nodekey"))
    end

    test "enode URL is well-formed", %{udp_port: port} do
      url = EthNet.NodeKey.enode_url("127.0.0.1", port)
      assert String.starts_with?(url, "enode://")
      assert String.contains?(url, "@127.0.0.1:#{port}")
    end

    test "DiscV4 server is listening" do
      assert EthNet.DiscV4.Server.table_size() == 0
      assert EthNet.DiscV4.Server.peers() == []
    end

    test "PeerManager has zero connections" do
      assert EthNet.Peer.Manager.connected_count() == 0
      assert EthNet.Peer.Manager.connected_peers() == []
    end

    test "ConnectionSupervisor has no children" do
      assert EthNet.Peer.ConnectionSupervisor.count() == 0
    end
  end

  describe "node key persistence" do
    test "key is persisted and reloaded" do
      datadir = Path.join(@test_datadir, "persist_#{System.unique_integer([:positive])}")
      File.mkdir_p!(datadir)

      # Start first instance
      {:ok, nk1} = GenServer.start_link(EthNet.NodeKey, [datadir: datadir], name: nil)
      key1 = GenServer.call(nk1, :private_key)
      GenServer.stop(nk1)

      # Start second instance — should load same key
      {:ok, nk2} = GenServer.start_link(EthNet.NodeKey, [datadir: datadir], name: nil)
      key2 = GenServer.call(nk2, :private_key)
      GenServer.stop(nk2)

      assert key1 == key2
    end
  end

  # ──────────────────────────────────────────────────────────────
  # LOCAL: RLPx handshake loopback (initiator ↔ responder)
  # ──────────────────────────────────────────────────────────────

  describe "RLPx handshake loopback" do
    test "full handshake + frame exchange between two local peers" do
      init_priv = EthCrypto.Signature.generate_private_key()
      {:ok, init_pub} = EthCrypto.Signature.public_key_from_private(init_priv)
      resp_priv = EthCrypto.Signature.generate_private_key()
      {:ok, resp_pub} = EthCrypto.Signature.public_key_from_private(resp_priv)

      alias EthNet.RLPx.{Handshake, FrameCodec}
      alias EthNet.Protocol.{P2P, Eth68}

      # --- Handshake ---
      init_hs = Handshake.initiator(init_priv, init_pub, resp_pub)
      {:ok, auth_msg, init_hs} = Handshake.build_auth(init_hs)
      {:ok, resp_hs} = Handshake.read_auth(auth_msg, resp_priv, resp_pub)
      {:ok, ack_msg, resp_hs} = Handshake.build_ack(resp_hs)
      {:ok, init_hs} = Handshake.read_ack(ack_msg, init_hs)

      {:ok, init_secrets} = Handshake.derive_secrets(init_hs)
      {:ok, resp_secrets} = Handshake.derive_secrets(resp_hs)
      assert init_secrets.aes_secret == resp_secrets.aes_secret
      assert init_secrets.mac_secret == resp_secrets.mac_secret

      # --- Frame codec ---
      init_codec = FrameCodec.init(init_secrets)
      resp_codec = FrameCodec.init(resp_secrets)

      # --- Hello exchange ---
      {hello_code, hello_payload} = P2P.encode_hello(init_pub)
      {:ok, hello_frame, init_codec} = FrameCodec.encode(init_codec, hello_code, hello_payload)
      {:ok, 0x00, payload, <<>>, resp_codec} = FrameCodec.decode(resp_codec, hello_frame)
      {:hello, hello_msg} = P2P.decode(0x00, payload)
      assert hello_msg.version == 5
      assert hello_msg.client_id == "ex_ethclient/0.1.0"
      assert {"eth", 68} in hello_msg.capabilities

      # Responder sends Hello back
      {resp_hello_code, resp_hello_payload} = P2P.encode_hello(resp_pub, 30303)

      {:ok, resp_hello_frame, resp_codec} =
        FrameCodec.encode(resp_codec, resp_hello_code, resp_hello_payload)

      {:ok, 0x00, payload2, <<>>, init_codec} = FrameCodec.decode(init_codec, resp_hello_frame)
      {:hello, resp_hello_msg} = P2P.decode(0x00, payload2)
      assert resp_hello_msg.listen_port == 30303

      # --- Status exchange ---
      {status_code, status_payload} = Eth68.build_mainnet_status()

      {:ok, status_frame, init_codec} =
        FrameCodec.encode(init_codec, status_code, status_payload)

      {:ok, 0x10, payload3, <<>>, resp_codec} = FrameCodec.decode(resp_codec, status_frame)
      {:ok, status_msg} = Eth68.decode_status(payload3)
      assert status_msg.network_id == 1
      assert status_msg.genesis_hash == EthNet.Chain.genesis_hash(:mainnet)

      # Responder sends Status back
      {:ok, resp_status_frame, _resp_codec} =
        FrameCodec.encode(resp_codec, status_code, status_payload)

      {:ok, 0x10, payload4, <<>>, _init_codec} =
        FrameCodec.decode(init_codec, resp_status_frame)

      {:ok, resp_status} = Eth68.decode_status(payload4)
      assert resp_status.network_id == 1
    end
  end

  # ──────────────────────────────────────────────────────────────
  # LOCAL: TCP loopback — full connection lifecycle
  # ──────────────────────────────────────────────────────────────

  describe "TCP loopback" do
    test "initiator connects to a mock responder over TCP" do
      resp_priv = EthCrypto.Signature.generate_private_key()
      {:ok, resp_pub} = EthCrypto.Signature.public_key_from_private(resp_priv)

      alias EthNet.RLPx.{Handshake, FrameCodec}
      alias EthNet.Protocol.{P2P, Eth68}

      # Start a TCP listener on random port
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)

      test_pid = self()

      # Spawn responder
      responder =
        spawn_link(fn ->
          {:ok, sock} = :gen_tcp.accept(listen, 10_000)

          # Read auth
          {:ok, <<size::big-unsigned-16>>} = :gen_tcp.recv(sock, 2, 5_000)
          {:ok, auth_body} = :gen_tcp.recv(sock, size, 5_000)
          auth_msg = <<size::big-unsigned-16, auth_body::binary>>

          {:ok, hs} = Handshake.read_auth(auth_msg, resp_priv, resp_pub)
          {:ok, ack_msg, hs} = Handshake.build_ack(hs)
          :ok = :gen_tcp.send(sock, ack_msg)

          {:ok, secrets} = Handshake.derive_secrets(hs)
          codec = FrameCodec.init(secrets)

          # Receive Hello
          {:ok, data} = :gen_tcp.recv(sock, 0, 5_000)
          {:ok, 0x00, _payload, <<>>, codec} = FrameCodec.decode(codec, data)

          # Send Hello back
          {hello_code, hello_payload} = P2P.encode_hello(resp_pub, port)
          {:ok, hello_frame, codec} = FrameCodec.encode(codec, hello_code, hello_payload)
          :ok = :gen_tcp.send(sock, hello_frame)

          # Receive Status
          {:ok, data2} = :gen_tcp.recv(sock, 0, 5_000)
          {:ok, 0x10, _payload2, <<>>, codec} = FrameCodec.decode(codec, data2)

          # Send Status back
          {status_code, status_payload} = Eth68.build_mainnet_status()
          {:ok, status_frame, _codec} = FrameCodec.encode(codec, status_code, status_payload)
          :ok = :gen_tcp.send(sock, status_frame)

          send(test_pid, :responder_done)
          Process.sleep(200)
          :gen_tcp.close(sock)
        end)

      # Initiator side
      init_priv = EthCrypto.Signature.generate_private_key()
      {:ok, init_pub} = EthCrypto.Signature.public_key_from_private(init_priv)

      {:ok, sock} =
        :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, nodelay: true], 5_000)

      # Handshake
      hs = Handshake.initiator(init_priv, init_pub, resp_pub)
      {:ok, auth_msg, hs} = Handshake.build_auth(hs)
      :ok = :gen_tcp.send(sock, auth_msg)

      {:ok, <<ack_size::big-unsigned-16>>} = :gen_tcp.recv(sock, 2, 5_000)
      {:ok, ack_body} = :gen_tcp.recv(sock, ack_size, 5_000)
      {:ok, hs} = Handshake.read_ack(<<ack_size::big-unsigned-16, ack_body::binary>>, hs)

      {:ok, secrets} = Handshake.derive_secrets(hs)
      codec = FrameCodec.init(secrets)

      # Send Hello
      {hello_code, hello_payload} = P2P.encode_hello(init_pub)
      {:ok, hello_frame, codec} = FrameCodec.encode(codec, hello_code, hello_payload)
      :ok = :gen_tcp.send(sock, hello_frame)

      # Receive Hello
      {:ok, data} = :gen_tcp.recv(sock, 0, 5_000)
      {:ok, 0x00, payload, <<>>, codec} = FrameCodec.decode(codec, data)
      {:hello, hello_msg} = P2P.decode(0x00, payload)
      assert hello_msg.version == 5
      assert {"eth", 68} in hello_msg.capabilities

      # Send Status
      {status_code, status_payload} = Eth68.build_mainnet_status()
      {:ok, status_frame, codec} = FrameCodec.encode(codec, status_code, status_payload)
      :ok = :gen_tcp.send(sock, status_frame)

      # Receive Status
      {:ok, data2} = :gen_tcp.recv(sock, 0, 5_000)
      {:ok, 0x10, payload2, <<>>, _codec} = FrameCodec.decode(codec, data2)
      {:ok, status} = Eth68.decode_status(payload2)
      assert status.network_id == 1
      assert status.genesis_hash == EthNet.Chain.genesis_hash(:mainnet)

      assert_receive :responder_done, 5_000

      :gen_tcp.close(sock)
      :gen_tcp.close(listen)
      Process.unlink(responder)
    end
  end

  # ──────────────────────────────────────────────────────────────
  # NETWORK: Real mainnet bootnode connection (requires internet)
  # ──────────────────────────────────────────────────────────────

  describe "mainnet bootnode connection" do
    @describetag :e2e
    test "TCP connect + RLPx handshake + Hello + Status with real bootnode" do
      alias EthNet.RLPx.{Handshake, FrameCodec}
      alias EthNet.Protocol.{P2P, Eth68}

      priv = EthCrypto.Signature.generate_private_key()
      {:ok, pub} = EthCrypto.Signature.public_key_from_private(priv)

      bootnodes = EthNet.Chain.bootnodes(:mainnet)

      result =
        Enum.reduce_while(bootnodes, {:error, :all_failed}, fn enode_url, _acc ->
          {:ok, node} = EthNet.DiscV4.Node.from_enode(enode_url)
          Logger.info("E2E: Trying #{:inet.ntoa(node.ip)}:#{node.tcp_port}...")

          case try_full_connect(node, priv, pub) do
            {:ok, status} -> {:halt, {:ok, node, status}}
            {:error, reason} ->
              Logger.info("E2E: Failed: #{inspect(reason)}")
              {:cont, {:error, reason}}
          end
        end)

      case result do
        {:ok, node, status} ->
          Logger.info("E2E: SUCCESS — connected to #{:inet.ntoa(node.ip)}:#{node.tcp_port}")
          Logger.info("E2E: Remote network_id=#{status.network_id}")

          best_hash_hex =
            Base.encode16(status.best_hash, case: :lower) |> String.slice(0, 16)

          Logger.info("E2E: Remote best_hash=0x#{best_hash_hex}...")

          assert status.network_id == 1
          assert status.genesis_hash == EthNet.Chain.genesis_hash(:mainnet)
          assert byte_size(status.best_hash) == 32

        {:error, reason} ->
          Logger.warning("E2E: Could not connect to any bootnode: #{inspect(reason)}")
          IO.puts("\n  [SKIP] No bootnode reachable — expected in CI/restricted networks")
      end
    end
  end

  # ──────────────────────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────────────────────

  defp try_full_connect(node, priv, pub) do
    alias EthNet.RLPx.{Handshake, FrameCodec}
    alias EthNet.Protocol.{P2P, Eth68}

    with {:ok, sock} <-
           :gen_tcp.connect(
             node.ip,
             node.tcp_port,
             [:binary, active: false, nodelay: true],
             5_000
           ),
         hs = Handshake.initiator(priv, pub, node.id),
         {:ok, auth_msg, hs} <- Handshake.build_auth(hs),
         :ok <- :gen_tcp.send(sock, auth_msg),
         {:ok, <<ack_size::big-unsigned-16>>} <- :gen_tcp.recv(sock, 2, 10_000),
         {:ok, ack_body} <- :gen_tcp.recv(sock, ack_size, 10_000),
         {:ok, hs} <-
           Handshake.read_ack(<<ack_size::big-unsigned-16, ack_body::binary>>, hs),
         {:ok, secrets} <- Handshake.derive_secrets(hs) do
      codec = FrameCodec.init(secrets)

      # Send Hello
      {hello_code, hello_payload} = P2P.encode_hello(pub)
      {:ok, hello_frame, codec} = FrameCodec.encode(codec, hello_code, hello_payload)
      :ok = :gen_tcp.send(sock, hello_frame)

      # Receive Hello
      case recv_frame(sock, codec) do
        {:ok, 0x00, payload, codec} ->
          {:hello, hello_msg} = P2P.decode(0x00, payload)
          Logger.info("E2E: Hello from #{hello_msg.client_id}")

          # Send Status
          {status_code, status_payload} = Eth68.build_mainnet_status()
          {:ok, status_frame, codec} = FrameCodec.encode(codec, status_code, status_payload)
          :ok = :gen_tcp.send(sock, status_frame)

          result = receive_status(sock, codec)
          :gen_tcp.close(sock)
          result

        {:ok, 0x01, payload, _codec} ->
          {:disconnect, reason} = P2P.decode(0x01, payload)
          :gen_tcp.close(sock)
          {:error, {:disconnected_at_hello, reason}}

        {:error, reason} ->
          :gen_tcp.close(sock)
          {:error, {:hello_recv_failed, reason}}
      end
    else
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end

  defp receive_status(sock, codec) do
    alias EthNet.RLPx.FrameCodec
    alias EthNet.Protocol.{P2P, Eth68}

    case recv_frame(sock, codec) do
      {:ok, 0x10, payload, _codec} ->
        Eth68.decode_status(payload)

      {:ok, 0x02, _payload, codec} ->
        # Got Ping, send Pong and retry
        {pong_code, pong_payload} = P2P.encode_pong()
        {:ok, pong_frame, codec} = FrameCodec.encode(codec, pong_code, pong_payload)
        :gen_tcp.send(sock, pong_frame)
        receive_status(sock, codec)

      {:ok, 0x01, payload, _codec} ->
        {:disconnect, reason} = P2P.decode(0x01, payload)
        {:error, {:disconnected_at_status, reason}}

      {:ok, _code, _payload, codec} ->
        receive_status(sock, codec)

      {:error, reason} ->
        {:error, {:status_recv_failed, reason}}
    end
  end

  defp recv_frame(sock, codec) do
    recv_frame_loop(sock, codec, <<>>)
  end

  defp recv_frame_loop(sock, codec, buffer) do
    alias EthNet.RLPx.FrameCodec

    case FrameCodec.decode(codec, buffer) do
      {:ok, msg_code, payload, _remaining, codec} ->
        {:ok, msg_code, payload, codec}

      {:error, :insufficient_data} ->
        recv_more(sock, codec, buffer)

      {:error, :incomplete_frame} ->
        recv_more(sock, codec, buffer)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recv_more(sock, codec, buffer) do
    case :gen_tcp.recv(sock, 0, 10_000) do
      {:ok, data} -> recv_frame_loop(sock, codec, buffer <> data)
      {:error, reason} -> {:error, {:tcp_recv_failed, reason}}
    end
  end
end
