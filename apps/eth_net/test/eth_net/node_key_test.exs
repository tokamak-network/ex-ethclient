defmodule EthNet.NodeKeyTest do
  use ExUnit.Case, async: false

  alias EthNet.NodeKey

  @test_datadir Path.join(System.tmp_dir!(), "eth_net_nodekey_test_#{:rand.uniform(100_000)}")

  setup do
    File.rm_rf!(@test_datadir)
    File.mkdir_p!(@test_datadir)

    start_supervised!({NodeKey, datadir: @test_datadir})

    on_exit(fn -> File.rm_rf!(@test_datadir) end)
    :ok
  end

  test "generates a 32-byte private key" do
    privkey = NodeKey.private_key()
    assert byte_size(privkey) == 32
  end

  test "derives a 64-byte public key" do
    pubkey = NodeKey.public_key()
    assert byte_size(pubkey) == 64
  end

  test "node_id equals public_key" do
    assert NodeKey.node_id() == NodeKey.public_key()
  end

  test "persists key to file" do
    privkey = NodeKey.private_key()
    keyfile = Path.join(@test_datadir, "nodekey")

    assert File.exists?(keyfile)
    assert File.read!(keyfile) == privkey
  end

  test "enode_url returns valid format" do
    url = NodeKey.enode_url("127.0.0.1", 30303)
    assert String.starts_with?(url, "enode://")
    assert String.contains?(url, "@127.0.0.1:30303")
    # Node ID is 64 bytes = 128 hex chars
    [_, id_and_host] = String.split(url, "://")
    [id_hex, _host] = String.split(id_and_host, "@")
    assert String.length(id_hex) == 128
  end
end
