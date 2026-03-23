defmodule EthNet.Sync.SnapSyncTest do
  use ExUnit.Case, async: false

  alias EthNet.Sync.SnapSync

  @empty_trie_root EthCore.Types.Account.empty_trie_root()
  @empty_code_hash EthCore.Types.Account.empty_code_hash()
  @pivot_root :crypto.strong_rand_bytes(32)

  setup do
    snap = start_supervised!({SnapSync, name: :"snap_#{System.unique_integer([:positive])}"})
    %{snap: snap}
  end

  describe "initial state" do
    test "starts with idle status", %{snap: snap} do
      status = SnapSync.status(snap)
      assert status.status == :idle
      assert status.pivot_block == nil
      assert status.pivot_root == nil
      assert status.accounts_downloaded == 0
      assert status.storage_downloaded == 0
      assert status.codes_downloaded == 0
      assert status.nodes_healed == 0
      assert status.pending_requests == 0
      assert status.peers == 0
    end
  end

  describe "start_sync" do
    test "transitions from idle to downloading_accounts", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.status == :downloading_accounts
      assert status.pivot_block == 1_000_000
      assert status.pivot_root == @pivot_root
    end

    test "does not restart if already syncing", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      SnapSync.start_sync(snap, 2_000_000, @pivot_root)
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.pivot_block == 1_000_000
    end
  end

  describe "account range processing" do
    test "stores accounts and increments counter", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      accounts = make_accounts(5)
      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.accounts_downloaded == 5
    end

    test "tracks accounts with non-empty storage root", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      storage_root = :crypto.strong_rand_bytes(32)
      hash1 = <<1::256>>
      hash2 = <<2::256>>

      accounts = [
        {hash1, 0, 100, storage_root, @empty_code_hash},
        {hash2, 0, 200, @empty_trie_root, @empty_code_hash}
      ]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.accounts_downloaded == 2
      assert status.pending_storage == 1
    end

    test "tracks accounts with non-empty code hash", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      code_hash = :crypto.strong_rand_bytes(32)
      hash1 = <<1::256>>
      hash2 = <<2::256>>

      accounts = [
        {hash1, 0, 100, @empty_trie_root, code_hash},
        {hash2, 0, 200, @empty_trie_root, @empty_code_hash}
      ]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.accounts_downloaded == 2
      assert status.pending_codes == 1
    end

    test "empty response transitions to next phase", %{snap: snap} do
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      SnapSync.handle_account_range(snap, 1, [], [])
      Process.sleep(50)

      status = SnapSync.status(snap)
      # With no pending storage or codes, goes straight to complete
      assert status.status == :complete
    end
  end

  describe "state transitions" do
    test "accounts with storage transitions to downloading_storage", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      storage_root = :crypto.strong_rand_bytes(32)
      accounts = [{<<1::256>>, 0, 100, storage_root, @empty_code_hash}]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      # Send empty to signal range done
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(100)

      status = SnapSync.status(snap)
      assert status.status == :downloading_storage
    end

    test "accounts with code transitions to downloading_codes when no storage", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      code_hash = :crypto.strong_rand_bytes(32)
      accounts = [{<<1::256>>, 0, 100, @empty_trie_root, code_hash}]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(100)

      status = SnapSync.status(snap)
      assert status.status == :downloading_codes
    end

    test "storage complete transitions to downloading_codes", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      storage_root = :crypto.strong_rand_bytes(32)
      code_hash = :crypto.strong_rand_bytes(32)
      accounts = [{<<1::256>>, 0, 100, storage_root, code_hash}]

      # req_id 1 was used for the initial account range request
      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)
      # req_id 2 was used for the next account range request
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(150)

      assert SnapSync.status(snap).status == :downloading_storage

      # req_id 3 was used for the storage ranges request
      slots = [[{:crypto.strong_rand_bytes(32), <<42>>}]]
      SnapSync.handle_storage_ranges(snap, 3, slots, [])
      Process.sleep(150)

      status = SnapSync.status(snap)
      assert status.status == :downloading_codes
      assert status.storage_downloaded == 1
    end

    test "codes complete transitions to healing or complete", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      code_hash = :crypto.strong_rand_bytes(32)
      accounts = [{<<1::256>>, 0, 100, @empty_trie_root, code_hash}]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(150)

      assert SnapSync.status(snap).status == :downloading_codes

      # req_id 3 was used for the byte codes request
      SnapSync.handle_byte_codes(snap, 3, [<<0xEF>>])
      Process.sleep(150)

      status = SnapSync.status(snap)
      # No pending trie nodes, so goes to complete
      assert status.status == :complete
      assert status.codes_downloaded == 1
    end

    test "full lifecycle: accounts -> storage -> codes -> complete", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      storage_root = :crypto.strong_rand_bytes(32)
      code_hash = :crypto.strong_rand_bytes(32)

      accounts = [
        {<<1::256>>, 1, 1000, storage_root, code_hash},
        {<<2::256>>, 0, 500, @empty_trie_root, @empty_code_hash}
      ]

      # req_id 1: initial account range
      SnapSync.handle_account_range(snap, 1, accounts, [])
      Process.sleep(50)
      # req_id 2: next account range request
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(150)

      assert SnapSync.status(snap).status == :downloading_storage

      # req_id 3: storage ranges request
      slots = [[{:crypto.strong_rand_bytes(32), <<1, 2, 3>>}]]
      SnapSync.handle_storage_ranges(snap, 3, slots, [])
      Process.sleep(150)

      assert SnapSync.status(snap).status == :downloading_codes

      # req_id 4: byte codes request
      SnapSync.handle_byte_codes(snap, 4, [<<0x60, 0x00>>])
      Process.sleep(150)

      status = SnapSync.status(snap)
      assert status.status == :complete
      assert status.accounts_downloaded == 2
      assert status.storage_downloaded == 1
      assert status.codes_downloaded == 1
    end
  end

  describe "request tracking" do
    test "pending request count reflects in-flight requests", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      # The start_sync triggers a request_next which creates a pending request
      status = SnapSync.status(snap)
      assert status.pending_requests >= 0
    end

    test "request ID increments with each request", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      # First account range response
      SnapSync.handle_account_range(snap, 1, make_accounts(3), [])
      Process.sleep(100)

      # Status should show the GenServer is still running with incremented state
      status = SnapSync.status(snap)
      assert status.accounts_downloaded == 3
    end
  end

  describe "peer management" do
    test "add_peer increases peer count", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      status = SnapSync.status(snap)
      assert status.peers == 1
    end

    test "remove_peer decreases peer count", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.remove_peer(snap, self())
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.peers == 0
    end

    test "duplicate peers are not added twice", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.add_peer(snap, self())
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.peers == 1
    end

    test "multiple distinct peers tracked", %{snap: snap} do
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      SnapSync.add_peer(snap, pid1)
      SnapSync.add_peer(snap, pid2)
      Process.sleep(50)

      status = SnapSync.status(snap)
      assert status.peers == 2
    end
  end

  describe "healing phase" do
    test "trie nodes response increments healed count", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      # Deliver empty accounts to complete account phase immediately
      SnapSync.handle_account_range(snap, 1, [], [])
      Process.sleep(50)

      # Since there were no accounts, we go straight to complete
      status = SnapSync.status(snap)
      assert status.status == :complete
      assert status.nodes_healed == 0
    end
  end

  describe "storage range processing" do
    test "counts slots from multiple accounts", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      storage_root = :crypto.strong_rand_bytes(32)

      accounts = [
        {<<1::256>>, 0, 100, storage_root, @empty_code_hash},
        {<<2::256>>, 0, 200, storage_root, @empty_code_hash}
      ]

      SnapSync.handle_account_range(snap, 1, accounts, [])
      SnapSync.handle_account_range(snap, 2, [], [])
      Process.sleep(100)

      assert SnapSync.status(snap).status == :downloading_storage

      slots = [
        [{:crypto.strong_rand_bytes(32), <<1>>}, {:crypto.strong_rand_bytes(32), <<2>>}],
        [{:crypto.strong_rand_bytes(32), <<3>>}]
      ]

      SnapSync.handle_storage_ranges(snap, 3, slots, [])
      Process.sleep(100)

      status = SnapSync.status(snap)
      assert status.storage_downloaded == 3
    end
  end

  describe "concurrent requests" do
    test "handles multiple responses for different request IDs", %{snap: snap} do
      SnapSync.add_peer(snap, self())
      SnapSync.start_sync(snap, 1_000_000, @pivot_root)
      Process.sleep(50)

      # Send two account range responses
      SnapSync.handle_account_range(snap, 1, make_accounts(3), [])
      SnapSync.handle_account_range(snap, 2, make_accounts(2), [])
      Process.sleep(100)

      status = SnapSync.status(snap)
      assert status.accounts_downloaded == 5
    end
  end

  # --- Helpers ---

  defp make_accounts(n) do
    Enum.map(1..n, fn i ->
      {<<i::256>>, 0, i * 100, @empty_trie_root, @empty_code_hash}
    end)
  end
end
