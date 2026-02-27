defmodule EthNet.Protocol.Eth68Test do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Eth68

  test "Status encode/decode roundtrip" do
    genesis = EthNet.Chain.genesis_hash(:mainnet)
    fork_id = EthNet.ForkID.compute(:mainnet, 0, 0)

    params = %{
      network_id: 1,
      total_difficulty: 58_750_000_000_000_000_000_000,
      best_hash: genesis,
      genesis_hash: genesis,
      fork_id: fork_id
    }

    {code, payload} = Eth68.encode_status(params)
    assert code == Eth68.status_code()

    {:ok, decoded} = Eth68.decode_status(payload)
    assert decoded.version == 68
    assert decoded.network_id == 1
    assert decoded.total_difficulty == 58_750_000_000_000_000_000_000
    assert decoded.best_hash == genesis
    assert decoded.genesis_hash == genesis
    assert decoded.fork_id == fork_id
  end

  test "build_mainnet_status produces valid Status" do
    {code, payload} = Eth68.build_mainnet_status()
    assert code == 0x10

    {:ok, decoded} = Eth68.decode_status(payload)
    assert decoded.network_id == 1
    assert decoded.genesis_hash == EthNet.Chain.genesis_hash(:mainnet)
  end

  test "eth_message? identifies eth sub-protocol" do
    assert Eth68.eth_message?(0x10)
    assert Eth68.eth_message?(0x11)
    refute Eth68.eth_message?(0x00)
    refute Eth68.eth_message?(0x0F)
  end
end
