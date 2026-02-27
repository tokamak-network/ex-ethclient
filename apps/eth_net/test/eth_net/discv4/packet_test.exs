defmodule EthNet.DiscV4.PacketTest do
  use ExUnit.Case, async: true

  alias EthNet.DiscV4.Packet

  setup do
    privkey = EthCrypto.Signature.generate_private_key()
    {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)
    %{privkey: privkey, pubkey: pubkey}
  end

  describe "PING encode/decode roundtrip" do
    test "encodes and decodes a PING packet", %{privkey: privkey, pubkey: pubkey} do
      from_ip = {192, 168, 1, 1}
      to_ip = {10, 0, 0, 1}

      {:ok, data} = Packet.encode_ping(from_ip, 30303, 30303, to_ip, 30303, 30303, privkey)

      assert {:ok, {:ping, msg, sender_id, _hash}} = Packet.decode(data)
      assert sender_id == pubkey
      assert msg.from.ip == from_ip
      assert msg.to.ip == to_ip
      assert msg.version == 4
    end
  end

  describe "PONG encode/decode roundtrip" do
    test "encodes and decodes a PONG packet", %{privkey: privkey, pubkey: pubkey} do
      to_ip = {10, 0, 0, 1}
      ping_hash = :crypto.strong_rand_bytes(32)

      {:ok, data} = Packet.encode_pong(to_ip, 30303, 30303, ping_hash, privkey)

      assert {:ok, {:pong, msg, sender_id, _hash}} = Packet.decode(data)
      assert sender_id == pubkey
      assert msg.ping_hash == ping_hash
    end
  end

  describe "FINDNODE encode/decode roundtrip" do
    test "encodes and decodes a FINDNODE packet", %{privkey: privkey, pubkey: pubkey} do
      target = :crypto.strong_rand_bytes(64)

      {:ok, data} = Packet.encode_findnode(target, privkey)

      assert {:ok, {:findnode, msg, sender_id, _hash}} = Packet.decode(data)
      assert sender_id == pubkey
      assert msg.target == target
    end
  end

  describe "NEIGHBOURS encode/decode roundtrip" do
    test "encodes and decodes a NEIGHBOURS packet", %{privkey: privkey, pubkey: pubkey} do
      nodes = [
        %EthNet.DiscV4.Node{
          id: :crypto.strong_rand_bytes(64),
          ip: {192, 168, 1, 100},
          udp_port: 30303,
          tcp_port: 30303
        }
      ]

      {:ok, data} = Packet.encode_neighbours(nodes, privkey)

      assert {:ok, {:neighbours, msg, sender_id, _hash}} = Packet.decode(data)
      assert sender_id == pubkey
      assert length(msg.nodes) == 1
      [node] = msg.nodes
      assert node.ip == {192, 168, 1, 100}
      assert node.udp_port == 30303
    end
  end

  describe "packet integrity" do
    test "rejects tampered packets", %{privkey: privkey} do
      {:ok, data} =
        Packet.encode_ping({0, 0, 0, 0}, 30303, 30303, {1, 2, 3, 4}, 30303, 30303, privkey)

      # Tamper with a byte in the signature
      <<hash::binary-size(32), byte, rest::binary>> = data
      tampered = hash <> <<Bitwise.bxor(byte, 0xFF)>> <> rest

      assert {:error, :invalid_hash} = Packet.decode(tampered)
    end

    test "rejects too-short packets" do
      assert {:error, :invalid_packet_size} = Packet.decode(<<0::256>>)
    end
  end
end
