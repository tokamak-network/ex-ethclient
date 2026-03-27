defmodule EthNet.DiscV5.PacketTest do
  use ExUnit.Case, async: true

  alias EthNet.DiscV5.{Packet, Session}

  describe "message encoding/decoding" do
    test "PING encode/decode roundtrip" do
      payload = Packet.encode_ping(1, 100)
      assert {:ok, {:ping, msg}} = Packet.decode_message(payload)
      assert msg.request_id == 1
      assert msg.enr_seq == 100
    end

    test "PONG encode/decode roundtrip" do
      payload = Packet.encode_pong(42, 10, {192, 168, 1, 1}, 30303)
      assert {:ok, {:pong, msg}} = Packet.decode_message(payload)
      assert msg.request_id == 42
      assert msg.enr_seq == 10
      assert msg.recipient_ip == {192, 168, 1, 1}
      assert msg.recipient_port == 30303
    end

    test "FINDNODE encode/decode roundtrip" do
      payload = Packet.encode_findnode(7, [255, 254, 253])
      assert {:ok, {:findnode, msg}} = Packet.decode_message(payload)
      assert msg.request_id == 7
      assert msg.distances == [255, 254, 253]
    end

    test "NODES encode/decode roundtrip" do
      enr_records = [<<>>, <<>>]
      payload = Packet.encode_nodes(3, 1, enr_records)
      assert {:ok, {:nodes, msg}} = Packet.decode_message(payload)
      assert msg.request_id == 3
      assert msg.total == 1
      assert length(msg.enr_records) == 2
    end

    test "PING with zero values" do
      payload = Packet.encode_ping(0, 0)
      assert {:ok, {:ping, msg}} = Packet.decode_message(payload)
      assert msg.request_id == 0
      assert msg.enr_seq == 0
    end

    test "FINDNODE with empty distances" do
      payload = Packet.encode_findnode(1, [])
      assert {:ok, {:findnode, msg}} = Packet.decode_message(payload)
      assert msg.distances == []
    end

    test "returns error for empty message" do
      assert {:error, :empty_message} = Packet.decode_message(<<>>)
    end

    test "returns error for unknown message type" do
      assert {:error, :unknown_message_type} = Packet.decode_message(<<99, 0xC0>>)
    end
  end

  describe "WHOAREYOU packet encoding" do
    test "encodes a WHOAREYOU packet" do
      dest_node_id = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)
      id_nonce = :crypto.strong_rand_bytes(16)

      packet = Packet.encode_whoareyou(dest_node_id, nonce, id_nonce, 42)

      # WHOAREYOU: masking-iv (16) + masked-header
      # static-header: "discv5"(6) + version(2) + flag(1) + nonce(12) + authdata-size(2) = 23
      # auth-data: id-nonce(16) + enr-seq(8) = 24
      # Total masked: 23 + 24 = 47
      assert byte_size(packet) == 16 + 47
    end

    test "WHOAREYOU decode roundtrip" do
      dest_node_id = :crypto.strong_rand_bytes(32)
      nonce = :crypto.strong_rand_bytes(12)
      id_nonce = :crypto.strong_rand_bytes(16)
      enr_seq = 42

      packet = Packet.encode_whoareyou(dest_node_id, nonce, id_nonce, enr_seq)
      assert {:ok, {1, data}} = Packet.decode(packet, dest_node_id)
      assert data.id_nonce == id_nonce
      assert data.enr_seq == enr_seq
      assert data.nonce == nonce
    end
  end

  describe "ordinary message packet encoding" do
    test "encodes and decodes an ordinary message packet" do
      src_id = :crypto.strong_rand_bytes(32)
      dest_id = :crypto.strong_rand_bytes(32)
      init_key = :crypto.strong_rand_bytes(16)
      recip_key = :crypto.strong_rand_bytes(16)
      nonce = :crypto.strong_rand_bytes(12)

      session = Session.from_keys(src_id, init_key, recip_key)
      message = Packet.encode_ping(1, 5)

      assert {:ok, packet, _session} =
               Packet.encode_message_packet(message, dest_id, nonce, session)

      # Packet: masking-iv(16) + masked-header + encrypted-message
      assert byte_size(packet) > 16 + 23

      # Decode the packet using the dest_id to unmask
      assert {:ok, {0, data}} = Packet.decode(packet, dest_id)
      assert data.src_id == src_id
      assert data.nonce == nonce
      assert is_binary(data.encrypted_message)
    end
  end

  describe "handshake packet encoding" do
    test "encodes a handshake packet" do
      src_id = :crypto.strong_rand_bytes(32)
      dest_id = :crypto.strong_rand_bytes(32)
      init_key = :crypto.strong_rand_bytes(16)
      recip_key = :crypto.strong_rand_bytes(16)
      nonce = :crypto.strong_rand_bytes(12)
      id_signature = :crypto.strong_rand_bytes(64)
      ephemeral_pubkey = :crypto.strong_rand_bytes(33)

      session = Session.from_keys(src_id, init_key, recip_key)
      message = Packet.encode_ping(1, 0)

      assert {:ok, packet, _session} =
               Packet.encode_handshake_packet(
                 message,
                 dest_id,
                 nonce,
                 src_id,
                 id_signature,
                 ephemeral_pubkey,
                 nil,
                 session
               )

      assert {:ok, {2, data}} = Packet.decode(packet, dest_id)
      assert data.src_id == src_id
      assert data.nonce == nonce
      assert data.id_signature == id_signature
      assert data.ephemeral_pubkey == ephemeral_pubkey
    end
  end

  describe "packet decode error handling" do
    test "returns error for packet too short" do
      assert {:error, :packet_too_short} = Packet.decode(<<0::64>>, :crypto.strong_rand_bytes(32))
    end

    test "returns error for empty packet" do
      assert {:error, :packet_too_short} = Packet.decode(<<>>, :crypto.strong_rand_bytes(32))
    end
  end

  describe "full encrypt/decrypt roundtrip" do
    test "sender encrypts, receiver decrypts via packet" do
      src_id = :crypto.strong_rand_bytes(32)
      dest_id = :crypto.strong_rand_bytes(32)
      init_key = :crypto.strong_rand_bytes(16)
      recip_key = :crypto.strong_rand_bytes(16)
      nonce = :crypto.strong_rand_bytes(12)

      sender_session = Session.from_keys(src_id, init_key, recip_key)
      receiver_session = Session.from_keys(dest_id, recip_key, init_key)

      ping = Packet.encode_ping(99, 50)

      {:ok, packet, _sender_session} =
        Packet.encode_message_packet(ping, dest_id, nonce, sender_session)

      # Receiver decodes packet structure
      {:ok, {0, data}} = Packet.decode(packet, dest_id)

      # Receiver decrypts the message
      {:ok, plaintext} =
        Session.decrypt(receiver_session, data.encrypted_message, data.nonce, data.header)

      # Decode the decrypted message
      {:ok, {:ping, msg}} = Packet.decode_message(plaintext)
      assert msg.request_id == 99
      assert msg.enr_seq == 50
    end
  end
end
