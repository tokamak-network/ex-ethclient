defmodule EthNet.Protocol.P2PTest do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.P2P

  test "Hello encode/decode roundtrip" do
    node_id = :crypto.strong_rand_bytes(64)
    {code, payload} = P2P.encode_hello(node_id, 30303)

    assert code == P2P.hello_code()
    assert {:hello, msg} = P2P.decode(code, payload)
    assert msg.version == 5
    assert msg.client_id == "ex_ethclient/0.1.0"
    assert msg.capabilities == [{"eth", 68}]
    assert msg.listen_port == 30303
    assert msg.node_id == node_id
  end

  test "Disconnect encode/decode roundtrip" do
    {code, payload} = P2P.encode_disconnect(:too_many_peers)
    assert code == P2P.disconnect_code()
    assert {:disconnect, :too_many_peers} = P2P.decode(code, payload)
  end

  test "Ping encode/decode" do
    {code, payload} = P2P.encode_ping()
    assert code == P2P.ping_code()
    assert :ping = P2P.decode(code, payload)
  end

  test "Pong encode/decode" do
    {code, payload} = P2P.encode_pong()
    assert code == P2P.pong_code()
    assert :pong = P2P.decode(code, payload)
  end

  test "p2p_message? identifies base protocol" do
    assert P2P.p2p_message?(0x00)
    assert P2P.p2p_message?(0x01)
    assert P2P.p2p_message?(0x02)
    assert P2P.p2p_message?(0x03)
    refute P2P.p2p_message?(0x10)
    refute P2P.p2p_message?(0x04)
  end
end
