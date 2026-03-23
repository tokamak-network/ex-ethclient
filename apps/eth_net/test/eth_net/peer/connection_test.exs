defmodule EthNet.Peer.ConnectionTest do
  use ExUnit.Case, async: true

  test "Connection module is available" do
    assert Code.ensure_loaded?(EthNet.Peer.Connection)
  end

  test "Connection struct has expected fields" do
    conn = %EthNet.Peer.Connection{}
    assert conn.state == :connecting
    assert conn.buffer == <<>>
    assert conn.socket == nil
    assert conn.eth_version == nil
  end
end
