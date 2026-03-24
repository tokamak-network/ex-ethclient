defmodule EthChain.IntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias EthChain.{Config, Node}
  alias EthStorage.{Genesis, Store}

  describe "full node lifecycle" do
    test "initialize genesis and read chain head" do
      store_name = :"int_store_#{System.unique_integer([:positive])}"
      store = start_supervised!({Store, name: store_name})

      assert :ok = Genesis.initialize(store)
      assert {:ok, 0} = Store.get_latest_block_number(store)

      mempool_name = :"int_mempool_#{System.unique_integer([:positive])}"
      _mempool = start_supervised!({EthChain.Mempool, name: mempool_name})

      assert {:ok, head} = Node.chain_head(store)
      assert head.head_number == 0
      assert is_binary(head.head_hash)
      assert byte_size(head.head_hash) == 32
    end
  end

  describe "config" do
    test "mainnet returns default configuration" do
      config = Config.mainnet()
      assert config.chain_id == 1
      assert config.rpc_port == 8545
      assert config.p2p_port == 30303
      assert config.rpc_enabled == true
      assert config.max_peers == 25
      assert config.evm_module == EthVm.Nif
    end

    test "from_env applies overrides" do
      config = Config.from_env(port: 30304, rpc_port: 9545, rpc: false)
      assert config.p2p_port == 30304
      assert config.rpc_port == 9545
      assert config.rpc_enabled == false
      assert config.chain_id == 1
    end
  end
end
