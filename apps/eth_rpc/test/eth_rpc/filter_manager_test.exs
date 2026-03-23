defmodule EthRpc.FilterManagerTest do
  use ExUnit.Case, async: true

  alias EthRpc.FilterManager

  setup do
    name = :"filter_mgr_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = FilterManager.start_link(name: name)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{server: name}
  end

  describe "new_filter/2" do
    test "creates a log filter and returns a hex ID", %{server: server} do
      assert {:ok, filter_id} = FilterManager.new_filter(server, %{from_block: 0})
      assert String.starts_with?(filter_id, "0x")
    end

    test "returns unique IDs for each filter", %{server: server} do
      {:ok, id1} = FilterManager.new_filter(server, %{})
      {:ok, id2} = FilterManager.new_filter(server, %{})
      assert id1 != id2
    end
  end

  describe "new_block_filter/1" do
    test "creates a block filter", %{server: server} do
      assert {:ok, filter_id} = FilterManager.new_block_filter(server)
      assert String.starts_with?(filter_id, "0x")
    end
  end

  describe "new_pending_tx_filter/1" do
    test "creates a pending transaction filter", %{server: server} do
      assert {:ok, filter_id} = FilterManager.new_pending_tx_filter(server)
      assert String.starts_with?(filter_id, "0x")
    end
  end

  describe "get_filter_changes/2" do
    test "returns empty list initially for log filter", %{server: server} do
      {:ok, filter_id} = FilterManager.new_filter(server, %{})
      assert {:ok, []} = FilterManager.get_filter_changes(server, filter_id)
    end

    test "returns error for unknown filter ID", %{server: server} do
      assert {:error, :not_found} =
               FilterManager.get_filter_changes(server, "0xdeadbeef")
    end

    test "returns accumulated changes then clears them", %{server: server} do
      {:ok, filter_id} = FilterManager.new_filter(server, %{})

      FilterManager.add_change(server, filter_id, "log1")
      FilterManager.add_change(server, filter_id, "log2")
      # Give casts time to process
      :timer.sleep(10)

      assert {:ok, ["log1", "log2"]} =
               FilterManager.get_filter_changes(server, filter_id)

      # Second call returns empty (changes were drained)
      assert {:ok, []} = FilterManager.get_filter_changes(server, filter_id)
    end
  end

  describe "get_filter_logs/2" do
    test "returns accumulated logs for log filter", %{server: server} do
      {:ok, filter_id} = FilterManager.new_filter(server, %{})
      FilterManager.add_change(server, filter_id, "log_entry")
      :timer.sleep(10)

      assert {:ok, ["log_entry"]} = FilterManager.get_filter_logs(server, filter_id)
    end

    test "returns error for block filter", %{server: server} do
      {:ok, filter_id} = FilterManager.new_block_filter(server)
      assert {:error, :not_found} = FilterManager.get_filter_logs(server, filter_id)
    end

    test "returns error for unknown filter", %{server: server} do
      assert {:error, :not_found} =
               FilterManager.get_filter_logs(server, "0xbad")
    end
  end

  describe "uninstall_filter/2" do
    test "returns true when filter exists", %{server: server} do
      {:ok, filter_id} = FilterManager.new_filter(server, %{})
      assert FilterManager.uninstall_filter(server, filter_id) == true
    end

    test "returns false on second uninstall", %{server: server} do
      {:ok, filter_id} = FilterManager.new_filter(server, %{})
      assert FilterManager.uninstall_filter(server, filter_id) == true
      assert FilterManager.uninstall_filter(server, filter_id) == false
    end

    test "returns false for unknown filter", %{server: server} do
      assert FilterManager.uninstall_filter(server, "0xnonexist") == false
    end
  end

  describe "notify_new_block/2" do
    test "block filter receives new block hash", %{server: server} do
      {:ok, block_fid} = FilterManager.new_block_filter(server)
      {:ok, log_fid} = FilterManager.new_filter(server, %{})

      block_hash = <<1::256>>
      FilterManager.notify_new_block(server, block_hash)
      :timer.sleep(10)

      # Block filter gets the hash
      assert {:ok, [^block_hash]} =
               FilterManager.get_filter_changes(server, block_fid)

      # Log filter does not get block notifications
      assert {:ok, []} = FilterManager.get_filter_changes(server, log_fid)
    end
  end
end
