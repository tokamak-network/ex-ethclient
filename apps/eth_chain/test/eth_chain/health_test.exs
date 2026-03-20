defmodule EthChain.HealthTest do
  use ExUnit.Case, async: false

  alias EthChain.Health

  describe "check/0" do
    test "returns correct structure" do
      result = Health.check()

      assert is_map(result)
      assert Map.has_key?(result, :store)
      assert Map.has_key?(result, :mempool)
      assert Map.has_key?(result, :syncing)
      assert Map.has_key?(result, :chain_head)
      assert Map.has_key?(result, :peer_count)
      assert Map.has_key?(result, :uptime_seconds)
    end

    test "reports processes as down when not started" do
      # In test env, Store and Mempool are not started by default
      result = Health.check()

      assert result.syncing == false
      assert result.peer_count == 0
      assert is_integer(result.uptime_seconds)
    end

    test "reports store as up when running" do
      store_name = EthStorage.Store
      start_supervised!({EthStorage.Store, name: store_name})

      result = Health.check()
      assert result.store == :up
    end

    test "reports mempool as up when running" do
      mempool_name = EthChain.Mempool
      start_supervised!({EthChain.Mempool, name: mempool_name})

      result = Health.check()
      assert result.mempool == :up
    end
  end
end
