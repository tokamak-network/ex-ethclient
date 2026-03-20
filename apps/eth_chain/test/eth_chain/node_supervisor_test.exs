defmodule EthChain.NodeSupervisorTest do
  use ExUnit.Case, async: false

  alias EthChain.{Config, NodeSupervisor}

  describe "start_link/1" do
    test "starts supervisor with default config" do
      config = %Config{rpc_enabled: false}
      pid = start_supervised!({NodeSupervisor, config})

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "store is running after startup" do
      config = %Config{rpc_enabled: false}
      _pid = start_supervised!({NodeSupervisor, config})

      # Give the genesis task a moment to complete
      Process.sleep(100)

      assert Process.whereis(EthStorage.Store) |> is_pid()
    end

    test "mempool is running after startup" do
      config = %Config{rpc_enabled: false}
      _pid = start_supervised!({NodeSupervisor, config})

      assert Process.whereis(EthChain.Mempool) |> is_pid()
    end

    test "genesis is initialized after startup" do
      config = %Config{rpc_enabled: false}
      _pid = start_supervised!({NodeSupervisor, config})

      # Give the genesis task time to complete
      Process.sleep(200)

      assert {:ok, 0} = EthStorage.Store.get_latest_block_number()
    end
  end
end
