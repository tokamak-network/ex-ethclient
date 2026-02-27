defmodule EthNetTest do
  use ExUnit.Case

  test "EthNet module is loaded" do
    assert Code.ensure_loaded?(EthNet)
  end

  test "EthNet.Chain provides mainnet constants" do
    assert byte_size(EthNet.Chain.genesis_hash(:mainnet)) == 32
    assert EthNet.Chain.network_id(:mainnet) == 1
  end

  test "bootnodes have valid enode format" do
    for url <- EthNet.Chain.bootnodes(:mainnet) do
      assert {:ok, _node} = EthNet.DiscV4.Node.from_enode(url)
    end
  end
end
