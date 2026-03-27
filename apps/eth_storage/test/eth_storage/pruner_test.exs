defmodule EthStorage.PrunerTest do
  use ExUnit.Case, async: true

  alias EthStorage.{Pruner, Store}

  setup do
    store_name = :"store_#{:erlang.unique_integer([:positive])}"
    pruner_name = :"pruner_#{:erlang.unique_integer([:positive])}"

    {:ok, _store_pid} = Store.start_link(name: store_name)

    {:ok, _pruner_pid} =
      Pruner.start_link(
        name: pruner_name,
        store: store_name,
        retain_blocks: 3,
        auto_prune: false
      )

    %{store: store_name, pruner: pruner_name}
  end

  describe "start_link/1" do
    test "starts the pruner process", %{pruner: pruner} do
      assert Process.alive?(Process.whereis(pruner))
    end
  end

  describe "notify_new_block/3" do
    test "tracks new blocks", %{pruner: pruner} do
      :ok = Pruner.notify_new_block(pruner, 1, :crypto.strong_rand_bytes(32))
      :ok = Pruner.notify_new_block(pruner, 2, :crypto.strong_rand_bytes(32))

      {:ok, stats} = Pruner.stats(pruner)
      assert stats.latest_block == 2
    end
  end

  describe "track_trie_nodes/3" do
    test "records node hashes for a block", %{pruner: pruner} do
      hash1 = :crypto.strong_rand_bytes(32)
      hash2 = :crypto.strong_rand_bytes(32)
      :ok = Pruner.track_trie_nodes(pruner, 1, [hash1, hash2])
      :ok = Pruner.notify_new_block(pruner, 1, :crypto.strong_rand_bytes(32))

      {:ok, stats} = Pruner.stats(pruner)
      assert stats.latest_block == 1
    end
  end

  describe "prune/1" do
    test "returns zero when no blocks tracked", %{pruner: pruner} do
      assert {:ok, 0} = Pruner.prune(pruner)
    end

    test "returns zero when all blocks are within retention window", %{pruner: pruner} do
      for i <- 1..3 do
        Pruner.notify_new_block(pruner, i, :crypto.strong_rand_bytes(32))
        Pruner.track_trie_nodes(pruner, i, [:crypto.strong_rand_bytes(32)])
      end

      assert {:ok, 0} = Pruner.prune(pruner)
    end

    test "prunes trie nodes from blocks older than retention window",
         %{store: store, pruner: pruner} do
      # Create unique node hashes for old blocks
      old_hash1 = :crypto.strong_rand_bytes(32)
      old_hash2 = :crypto.strong_rand_bytes(32)

      # Store trie nodes in the store
      :ok = Store.put_trie_node(store, old_hash1, "node_data_1")
      :ok = Store.put_trie_node(store, old_hash2, "node_data_2")

      # Track blocks 1 and 2 with their nodes
      Pruner.track_trie_nodes(pruner, 1, [old_hash1])
      Pruner.notify_new_block(pruner, 1, :crypto.strong_rand_bytes(32))

      Pruner.track_trie_nodes(pruner, 2, [old_hash2])
      Pruner.notify_new_block(pruner, 2, :crypto.strong_rand_bytes(32))

      # Add blocks 3-6 to push blocks 1-2 out of retention (retain_blocks: 3)
      for i <- 3..6 do
        Pruner.notify_new_block(pruner, i, :crypto.strong_rand_bytes(32))
      end

      # Prune should remove old nodes
      {:ok, pruned} = Pruner.prune(pruner)
      assert pruned == 2

      # Verify nodes were deleted from store
      assert {:ok, nil} = Store.get_trie_node(store, old_hash1)
      assert {:ok, nil} = Store.get_trie_node(store, old_hash2)
    end

    test "does not prune nodes still referenced by retained blocks",
         %{store: store, pruner: pruner} do
      shared_hash = :crypto.strong_rand_bytes(32)
      old_only_hash = :crypto.strong_rand_bytes(32)

      :ok = Store.put_trie_node(store, shared_hash, "shared_node")
      :ok = Store.put_trie_node(store, old_only_hash, "old_only_node")

      # Block 1 has both shared and old-only nodes
      Pruner.track_trie_nodes(pruner, 1, [shared_hash, old_only_hash])
      Pruner.notify_new_block(pruner, 1, :crypto.strong_rand_bytes(32))

      # Block 5 also references the shared node
      Pruner.track_trie_nodes(pruner, 5, [shared_hash])
      Pruner.notify_new_block(pruner, 5, :crypto.strong_rand_bytes(32))

      # Push block 1 out of retention window (retain 3, latest 5, cutoff 2)
      {:ok, pruned} = Pruner.prune(pruner)
      assert pruned == 1

      # Shared node should still exist
      assert {:ok, "shared_node"} = Store.get_trie_node(store, shared_hash)
      # Old-only node should be deleted
      assert {:ok, nil} = Store.get_trie_node(store, old_only_hash)
    end

    test "updates pruning statistics after prune", %{store: store, pruner: pruner} do
      hash = :crypto.strong_rand_bytes(32)
      :ok = Store.put_trie_node(store, hash, "data")

      Pruner.track_trie_nodes(pruner, 1, [hash])
      Pruner.notify_new_block(pruner, 1, :crypto.strong_rand_bytes(32))

      for i <- 2..5 do
        Pruner.notify_new_block(pruner, i, :crypto.strong_rand_bytes(32))
      end

      {:ok, 1} = Pruner.prune(pruner)

      {:ok, stats} = Pruner.stats(pruner)
      assert stats.pruned_count == 1
      assert stats.latest_block == 5
      assert stats.last_pruned_at != nil
    end
  end

  describe "stats/1" do
    test "returns initial stats", %{pruner: pruner} do
      {:ok, stats} = Pruner.stats(pruner)
      assert stats.pruned_count == 0
      assert stats.retained_blocks == 0
      assert stats.latest_block == nil
      assert stats.last_pruned_at == nil
    end

    test "counts retained blocks correctly", %{pruner: pruner} do
      for i <- 1..5 do
        Pruner.notify_new_block(pruner, i, :crypto.strong_rand_bytes(32))
      end

      {:ok, stats} = Pruner.stats(pruner)
      # retain_blocks: 3, latest: 5, cutoff: 2, retained: blocks 2,3,4,5
      assert stats.retained_blocks == 4
      assert stats.latest_block == 5
    end
  end

  describe "store delete and count" do
    test "delete removes key from table", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      :ok = Store.put_trie_node(store, hash, "data")
      assert {:ok, "data"} = Store.get_trie_node(store, hash)

      :ok = Store.delete(store, :account_trie_nodes, hash)
      assert {:ok, nil} = Store.get_trie_node(store, hash)
    end

    test "count returns number of entries", %{store: store} do
      assert {:ok, 0} = Store.count(store, :account_trie_nodes)

      :ok = Store.put_trie_node(store, :crypto.strong_rand_bytes(32), "a")
      :ok = Store.put_trie_node(store, :crypto.strong_rand_bytes(32), "b")

      assert {:ok, 2} = Store.count(store, :account_trie_nodes)
    end
  end
end
