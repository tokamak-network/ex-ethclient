defmodule EthChain.ShutdownManagerTest do
  use ExUnit.Case, async: true

  alias EthChain.ShutdownManager

  describe "start_link/1" do
    test "starts with default options" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      assert {:ok, pid} = ShutdownManager.start_link(name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom shutdown timeout" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      assert {:ok, pid} = ShutdownManager.start_link(name: name, shutdown_timeout: 5_000)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns :running when freshly started" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      {:ok, _pid} = ShutdownManager.start_link(name: name)
      assert :running == ShutdownManager.status(name)
    end
  end

  describe "initiate_shutdown/1" do
    test "transitions from :running to :stopped" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"

      {:ok, _pid} =
        ShutdownManager.start_link(
          name: name,
          on_rpc_stop: fn -> :ok end,
          on_net_stop: fn -> :ok end,
          on_mempool_flush: fn -> :ok end,
          on_storage_flush: fn -> :ok end
        )

      assert :running == ShutdownManager.status(name)
      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert :stopped == ShutdownManager.status(name)
    end

    test "is idempotent when called multiple times" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"

      {:ok, _pid} =
        ShutdownManager.start_link(
          name: name,
          on_rpc_stop: fn -> :ok end,
          on_net_stop: fn -> :ok end,
          on_mempool_flush: fn -> :ok end,
          on_storage_flush: fn -> :ok end
        )

      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert :stopped == ShutdownManager.status(name)
    end

    test "executes shutdown callbacks in order" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      test_pid = self()

      {:ok, _pid} =
        ShutdownManager.start_link(
          name: name,
          on_rpc_stop: fn ->
            send(test_pid, {:step, 1})
            :ok
          end,
          on_net_stop: fn ->
            send(test_pid, {:step, 2})
            :ok
          end,
          on_mempool_flush: fn ->
            send(test_pid, {:step, 3})
            :ok
          end,
          on_storage_flush: fn ->
            send(test_pid, {:step, 4})
            :ok
          end
        )

      assert :ok == ShutdownManager.initiate_shutdown(name)

      assert_received {:step, 1}
      assert_received {:step, 2}
      assert_received {:step, 3}
      assert_received {:step, 4}
    end

    test "handles callback failures gracefully" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"

      {:ok, _pid} =
        ShutdownManager.start_link(
          name: name,
          on_rpc_stop: fn -> raise "RPC stop failed" end,
          on_net_stop: fn -> :ok end,
          on_mempool_flush: fn -> exit(:mempool_crash) end,
          on_storage_flush: fn -> :ok end
        )

      # Should not raise even when callbacks fail
      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert :stopped == ShutdownManager.status(name)
    end

    test "continues shutdown sequence when early callbacks fail" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      test_pid = self()

      {:ok, _pid} =
        ShutdownManager.start_link(
          name: name,
          on_rpc_stop: fn -> raise "boom" end,
          on_net_stop: fn -> raise "boom" end,
          on_mempool_flush: fn -> raise "boom" end,
          on_storage_flush: fn ->
            send(test_pid, :storage_flushed)
            :ok
          end
        )

      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert_received :storage_flushed
    end
  end

  describe "signal handling" do
    test "handles :sigterm signal message" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      test_pid = self()

      {:ok, pid} =
        ShutdownManager.start_link(
          name: name,
          halt_on_signal: false,
          on_rpc_stop: fn -> :ok end,
          on_net_stop: fn -> :ok end,
          on_mempool_flush: fn -> :ok end,
          on_storage_flush: fn ->
            send(test_pid, :shutdown_complete)
            :ok
          end
        )

      # Simulate a signal message (halt_on_signal: false prevents :init.stop)
      send(pid, {:system_signal, :sigterm})

      assert_receive :shutdown_complete, 5_000
    end

    test "ignores duplicate signal when already shutting down" do
      name = :"shutdown_mgr_#{:erlang.unique_integer([:positive])}"
      test_pid = self()
      call_count = :counters.new(1, [:atomics])

      {:ok, pid} =
        ShutdownManager.start_link(
          name: name,
          halt_on_signal: false,
          on_rpc_stop: fn -> :ok end,
          on_net_stop: fn -> :ok end,
          on_mempool_flush: fn -> :ok end,
          on_storage_flush: fn ->
            :counters.add(call_count, 1, 1)
            send(test_pid, :flushed)
            :ok
          end
        )

      # Initiate shutdown via call first
      assert :ok == ShutdownManager.initiate_shutdown(name)
      assert_receive :flushed

      # Now send a signal - should be ignored since already stopped
      send(pid, {:system_signal, :sigterm})

      # Give it time to process
      Process.sleep(50)
      assert :counters.get(call_count, 1) == 1
    end
  end
end
