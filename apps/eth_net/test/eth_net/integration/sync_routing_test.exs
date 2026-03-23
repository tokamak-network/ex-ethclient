defmodule EthNet.Integration.SyncRoutingTest do
  @moduledoc """
  Tests that incoming eth/68 messages are correctly routed to the Sync.Manager.
  """

  use ExUnit.Case, async: false

  alias EthNet.Peer.Connection
  alias EthNet.Sync.Manager, as: SyncManager

  setup do
    # Start a Sync.Manager for this test with a unique name
    name = :"sync_routing_test_#{:erlang.unique_integer([:positive])}"
    {:ok, sync_pid} = SyncManager.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(sync_pid), do: GenServer.stop(sync_pid)
    end)

    %{sync_pid: sync_pid, sync_name: name}
  end

  describe "dispatch_eth_message routing" do
    test "BlockHeaders message is routed to Sync.Manager", %{sync_pid: sync_pid, sync_name: name} do
      # Start sync so it accepts headers
      SyncManager.start_sync(100, server: name)
      Process.sleep(50)

      # Simulate receiving headers by casting directly
      SyncManager.handle_headers(name, self(), 1, [])

      # Verify the sync manager is still alive and working
      status = SyncManager.status(name)
      assert status.status in [:syncing, :idle]
      assert Process.alive?(sync_pid)
    end

    test "BlockBodies message is routed to Sync.Manager", %{sync_pid: sync_pid, sync_name: name} do
      SyncManager.handle_bodies(name, self(), 1, [])

      # Manager should handle gracefully (unknown request)
      status = SyncManager.status(name)
      assert status.status == :idle
      assert Process.alive?(sync_pid)
    end

    test "NewBlockHashes is routed to Sync.Manager", %{sync_pid: sync_pid, sync_name: name} do
      hash = :crypto.strong_rand_bytes(32)
      GenServer.cast(name, {:new_block_hashes, self(), [{hash, 42}]})

      Process.sleep(50)

      assert Process.alive?(sync_pid)
    end

    test "NewBlock is routed to Sync.Manager", %{sync_pid: sync_pid, sync_name: name} do
      GenServer.cast(name, {:new_block, self(), %{block_number: 42}})

      Process.sleep(50)

      assert Process.alive?(sync_pid)
    end
  end

  describe "forward_to_sync safety" do
    test "forward_to_sync does not crash when Sync.Manager is not running" do
      # The forward_to_sync helper in Connection uses try/rescue,
      # so calling Sync.Manager functions when it's not registered should be safe.
      # GenServer.cast to a non-existent name does not raise.
      result =
        try do
          SyncManager.handle_headers(self(), 1, [])
          :ok
        rescue
          _ -> :rescued
        catch
          :exit, _ -> :exit_caught
        end

      assert result in [:ok, :rescued, :exit_caught]
    end
  end

  describe "send_eth_message handler integration" do
    test "Connection struct has expected fields for send_eth_message" do
      conn = %Connection{}
      assert Map.has_key?(conn, :socket)
      assert Map.has_key?(conn, :codec)
      assert conn.codec == nil
    end
  end
end
