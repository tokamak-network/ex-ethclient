defmodule EthNet.DiscV5.ENRTest do
  use ExUnit.Case, async: true

  alias EthNet.DiscV5.ENR

  setup do
    privkey = EthCrypto.Signature.generate_private_key()
    {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)
    %{privkey: privkey, pubkey: pubkey}
  end

  describe "new/5" do
    test "creates a signed ENR record", %{privkey: privkey} do
      assert {:ok, enr} = ENR.new(1, {192, 168, 1, 1}, 30303, 30303, privkey)
      assert enr.seq == 1
      assert is_binary(enr.signature)
      assert byte_size(enr.signature) == 64
      assert enr.pairs["id"] == "v4"
      assert is_binary(enr.pairs["secp256k1"])
    end

    test "increments sequence number", %{privkey: privkey} do
      {:ok, enr} = ENR.new(42, {10, 0, 0, 1}, 9000, 9001, privkey)
      assert enr.seq == 42
    end
  end

  describe "encode/decode roundtrip" do
    test "encodes and decodes an ENR record", %{privkey: privkey} do
      {:ok, enr} = ENR.new(5, {10, 0, 0, 1}, 30303, 30304, privkey)
      encoded = ENR.encode(enr)

      assert {:ok, decoded} = ENR.decode(encoded)
      assert decoded.seq == 5
      assert decoded.pairs["id"] == "v4"
      assert decoded.signature == enr.signature
    end

    test "preserves IP address through encode/decode", %{privkey: privkey} do
      {:ok, enr} = ENR.new(1, {192, 168, 1, 100}, 30303, 30303, privkey)
      encoded = ENR.encode(enr)
      {:ok, decoded} = ENR.decode(encoded)

      assert {:ok, {192, 168, 1, 100}} = ENR.ip(decoded)
    end

    test "preserves ports through encode/decode", %{privkey: privkey} do
      {:ok, enr} = ENR.new(1, {10, 0, 0, 1}, 9000, 9001, privkey)
      encoded = ENR.encode(enr)
      {:ok, decoded} = ENR.decode(encoded)

      assert {:ok, 9000} = ENR.udp_port(decoded)
      assert {:ok, 9001} = ENR.tcp_port(decoded)
    end
  end

  describe "node_id/1" do
    test "returns keccak256 of compressed public key", %{privkey: privkey} do
      {:ok, enr} = ENR.new(1, {0, 0, 0, 0}, 30303, 30303, privkey)
      assert {:ok, node_id} = ENR.node_id(enr)
      assert byte_size(node_id) == 32
    end

    test "returns error when no public key present" do
      enr = %ENR{seq: 1, pairs: %{"id" => "v4"}}
      assert {:error, :no_public_key} = ENR.node_id(enr)
    end
  end

  describe "accessor functions" do
    test "ip/1 returns error for missing IP" do
      enr = %ENR{seq: 1, pairs: %{}}
      assert {:error, :no_ip} = ENR.ip(enr)
    end

    test "udp_port/1 returns error for missing port" do
      enr = %ENR{seq: 1, pairs: %{}}
      assert {:error, :no_udp_port} = ENR.udp_port(enr)
    end

    test "tcp_port/1 returns error for missing port" do
      enr = %ENR{seq: 1, pairs: %{}}
      assert {:error, :no_tcp_port} = ENR.tcp_port(enr)
    end

    test "seq/1 returns the sequence number" do
      enr = %ENR{seq: 42, pairs: %{}}
      assert ENR.seq(enr) == 42
    end
  end

  describe "decode/1 error handling" do
    test "returns error for invalid data" do
      assert {:error, :invalid_enr} = ENR.decode(<<0xFF>>)
    end

    test "returns error for empty data" do
      assert {:error, :invalid_enr} = ENR.decode(<<>>)
    end
  end
end
