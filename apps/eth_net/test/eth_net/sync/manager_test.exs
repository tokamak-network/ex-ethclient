defmodule EthNet.Sync.ManagerTest do
  use ExUnit.Case, async: false

  alias EthNet.Sync.Manager

  setup do
    start_supervised!(Manager)
    :ok
  end

  test "starts with idle status" do
    status = Manager.status()
    assert status.status == :idle
    assert status.target_block == 0
    assert status.current_block == 0
    assert status.pending_headers == 0
    assert status.pending_bodies == 0
  end

  test "start_sync changes status to syncing" do
    Manager.start_sync(1000)
    # Give the cast time to process
    Process.sleep(50)

    status = Manager.status()
    assert status.status == :syncing
    assert status.target_block == 1000
  end

  test "handle_headers stores downloaded headers" do
    Manager.start_sync(1000)
    Process.sleep(50)

    Manager.handle_headers(self(), 1, [<<1, 2, 3>>, <<4, 5, 6>>])
    Process.sleep(50)

    status = Manager.status()
    assert status.downloaded_headers == 2
  end

  test "handle_bodies stores downloaded bodies" do
    Manager.start_sync(1000)
    Process.sleep(50)

    Manager.handle_bodies(self(), 1, [<<10, 20>>, <<30, 40>>])
    Process.sleep(50)

    status = Manager.status()
    assert status.downloaded_bodies == 2
  end

  test "handle_new_block_hashes does not crash" do
    hash = :crypto.strong_rand_bytes(32)
    assert :ok == Manager.handle_new_block_hashes(self(), [{hash, 100}])
  end

  test "handle_new_block does not crash" do
    assert :ok == Manager.handle_new_block(self(), %{block: <<>>, total_difficulty: 0})
  end

  test "status reports pending counts" do
    status = Manager.status()
    assert is_integer(status.pending_headers)
    assert is_integer(status.pending_bodies)
    assert is_integer(status.downloaded_headers)
    assert is_integer(status.downloaded_bodies)
  end
end
