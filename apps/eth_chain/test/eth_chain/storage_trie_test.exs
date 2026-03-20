defmodule EthChain.StorageTrieTest do
  use ExUnit.Case, async: true

  alias EthChain.StorageTrie
  alias EthStorage.MPT.Trie

  describe "new/0" do
    test "creates an empty storage trie" do
      trie = StorageTrie.new()
      assert %Trie{} = trie
      assert Trie.root_hash(trie) == Trie.empty_root_hash()
    end
  end

  describe "apply_storage_updates/2" do
    test "adds a single storage slot" do
      trie = StorageTrie.new()
      slot_key = <<1::256>>
      slot_value = <<42::256>>

      assert {:ok, updated, root} =
               StorageTrie.apply_storage_updates(trie, %{slot_key => slot_value})

      assert root != Trie.empty_root_hash()
      assert byte_size(root) == 32

      # Should be retrievable
      assert {:ok, ^slot_value} = StorageTrie.get_storage(updated, slot_key)
    end

    test "adds multiple storage slots" do
      trie = StorageTrie.new()

      updates = %{
        <<1::256>> => <<100::256>>,
        <<2::256>> => <<200::256>>,
        <<3::256>> => <<300::256>>
      }

      assert {:ok, updated, root} = StorageTrie.apply_storage_updates(trie, updates)
      assert root != Trie.empty_root_hash()

      assert {:ok, <<100::256>>} = StorageTrie.get_storage(updated, <<1::256>>)
      assert {:ok, <<200::256>>} = StorageTrie.get_storage(updated, <<2::256>>)
      assert {:ok, <<300::256>>} = StorageTrie.get_storage(updated, <<3::256>>)
    end

    test "storage root changes when storage changes" do
      trie = StorageTrie.new()

      {:ok, _, root1} =
        StorageTrie.apply_storage_updates(trie, %{<<1::256>> => <<10::256>>})

      {:ok, _, root2} =
        StorageTrie.apply_storage_updates(trie, %{<<1::256>> => <<20::256>>})

      assert root1 != root2
    end

    test "empty updates return empty trie root" do
      trie = StorageTrie.new()
      assert {:ok, _, root} = StorageTrie.apply_storage_updates(trie, %{})
      assert root == Trie.empty_root_hash()
    end
  end

  describe "get_storage/2" do
    test "returns nil for non-existent key" do
      trie = StorageTrie.new()
      assert {:ok, nil} = StorageTrie.get_storage(trie, <<99::256>>)
    end
  end
end
