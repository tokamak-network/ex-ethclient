defmodule EthNet.Peer.ConnectionSendTest do
  @moduledoc """
  Tests for the {:send_eth_message, code, payload} handler in Connection.
  """

  use ExUnit.Case, async: true

  alias EthNet.Peer.Connection

  describe "handle_info {:send_eth_message, ...}" do
    test "sends data over TCP when codec is established" do
      # Create a loopback TCP pair
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      {:ok, server} = :gen_tcp.accept(listen)

      # Build a minimal codec using FrameCodec.init with fake secrets
      aes_secret = :crypto.strong_rand_bytes(32)
      mac_secret = :crypto.strong_rand_bytes(32)

      secrets = %{
        aes_secret: aes_secret,
        mac_secret: mac_secret,
        egress_mac: EthNet.RLPx.Mac.new(mac_secret),
        ingress_mac: EthNet.RLPx.Mac.new(mac_secret)
      }

      codec = EthNet.RLPx.FrameCodec.init(secrets)

      # Build a Connection state with the codec and client socket
      state = %Connection{
        socket: client,
        codec: codec,
        remote_ip: {127, 0, 0, 1},
        remote_port: port,
        state: :active,
        buffer: <<>>
      }

      # Simulate the handle_info call
      msg_code = 0x13
      payload = <<1, 2, 3>>

      result = Connection.handle_info({:send_eth_message, msg_code, payload}, state)
      assert {:noreply, new_state} = result
      assert new_state.codec != nil

      # Verify data was sent over TCP
      {:ok, data} = :gen_tcp.recv(server, 0, 1_000)
      assert byte_size(data) > 0

      :gen_tcp.close(client)
      :gen_tcp.close(server)
      :gen_tcp.close(listen)
    end

    test "logs warning when codec is nil" do
      state = %Connection{
        socket: nil,
        codec: nil,
        remote_ip: {127, 0, 0, 1},
        remote_port: 30303,
        state: :connecting,
        buffer: <<>>
      }

      result = Connection.handle_info({:send_eth_message, 0x13, <<1, 2, 3>>}, state)
      assert {:noreply, ^state} = result
    end

    test "handles TCP send error gracefully" do
      # Create a socket and close the remote end to cause send failure
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
      {:ok, server} = :gen_tcp.accept(listen)

      # Close the server side
      :gen_tcp.close(server)
      :gen_tcp.close(listen)

      # Build codec
      aes_secret = :crypto.strong_rand_bytes(32)
      mac_secret = :crypto.strong_rand_bytes(32)

      secrets = %{
        aes_secret: aes_secret,
        mac_secret: mac_secret,
        egress_mac: EthNet.RLPx.Mac.new(mac_secret),
        ingress_mac: EthNet.RLPx.Mac.new(mac_secret)
      }

      codec = EthNet.RLPx.FrameCodec.init(secrets)

      state = %Connection{
        socket: client,
        codec: codec,
        remote_ip: {127, 0, 0, 1},
        remote_port: port,
        state: :active,
        buffer: <<>>
      }

      # Send a large payload to increase likelihood of error on closed socket
      # Small payloads may succeed due to kernel buffering
      big_payload = :crypto.strong_rand_bytes(65_536)

      result = Connection.handle_info({:send_eth_message, 0x13, big_payload}, state)
      # Should return :noreply regardless of success or failure
      assert {:noreply, _state} = result

      :gen_tcp.close(client)
    end
  end
end
