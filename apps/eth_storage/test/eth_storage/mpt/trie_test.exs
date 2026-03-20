defmodule EthStorage.MPT.TrieTest do
  use ExUnit.Case, async: true

  alias EthStorage.MPT.Trie

  describe "empty trie" do
    test "has correct root hash (keccak256 of RLP empty string)" do
      trie = Trie.new()
      expected = EthCrypto.Hash.keccak256(ExRLP.encode(""))
      assert Trie.root_hash(trie) == expected
    end

    test "get returns nil for any key" do
      trie = Trie.new()
      assert {:ok, nil} = Trie.get(trie, "anykey")
    end

    test "empty_root_hash matches known constant" do
      # keccak256(RLP("")) = 56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421
      expected =
        Base.decode16!(
          "56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421",
          case: :upper
        )

      assert Trie.empty_root_hash() == expected
    end
  end

  describe "single key-value" do
    test "insert and retrieve" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "value1")
      assert {:ok, "value1"} = Trie.get(trie, "key1")
    end

    test "root hash changes after insert" do
      trie = Trie.new()
      empty_hash = Trie.root_hash(trie)
      trie = Trie.put(trie, "key1", "value1")
      assert Trie.root_hash(trie) != empty_hash
    end

    test "missing key returns nil" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "value1")
      assert {:ok, nil} = Trie.get(trie, "other")
    end
  end

  describe "multiple inserts" do
    test "inserts and retrieves multiple keys" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "val1")
      trie = Trie.put(trie, "key2", "val2")
      trie = Trie.put(trie, "key3", "val3")

      assert {:ok, "val1"} = Trie.get(trie, "key1")
      assert {:ok, "val2"} = Trie.get(trie, "key2")
      assert {:ok, "val3"} = Trie.get(trie, "key3")
    end

    test "overwrite existing key" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "old_value")
      trie = Trie.put(trie, "key1", "new_value")
      assert {:ok, "new_value"} = Trie.get(trie, "key1")
    end

    test "keys with common prefix" do
      trie = Trie.new()
      trie = Trie.put(trie, "abc", "val_abc")
      trie = Trie.put(trie, "abd", "val_abd")
      trie = Trie.put(trie, "xyz", "val_xyz")

      assert {:ok, "val_abc"} = Trie.get(trie, "abc")
      assert {:ok, "val_abd"} = Trie.get(trie, "abd")
      assert {:ok, "val_xyz"} = Trie.get(trie, "xyz")
    end

    test "keys where one is prefix of another" do
      trie = Trie.new()
      trie = Trie.put(trie, "ab", "short")
      trie = Trie.put(trie, "abc", "long")

      assert {:ok, "short"} = Trie.get(trie, "ab")
      assert {:ok, "long"} = Trie.get(trie, "abc")
    end

    test "root hash is deterministic regardless of insert order" do
      trie_a =
        Trie.new()
        |> Trie.put("key1", "val1")
        |> Trie.put("key2", "val2")
        |> Trie.put("key3", "val3")

      trie_b =
        Trie.new()
        |> Trie.put("key3", "val3")
        |> Trie.put("key1", "val1")
        |> Trie.put("key2", "val2")

      assert Trie.root_hash(trie_a) == Trie.root_hash(trie_b)
    end
  end

  describe "delete" do
    test "delete from empty trie" do
      trie = Trie.new()
      trie = Trie.delete(trie, "key1")
      assert Trie.root_hash(trie) == Trie.empty_root_hash()
    end

    test "delete single key returns to empty" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "value1")
      trie = Trie.delete(trie, "key1")
      assert Trie.root_hash(trie) == Trie.empty_root_hash()
      assert {:ok, nil} = Trie.get(trie, "key1")
    end

    test "delete non-existent key is no-op" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "value1")
      hash_before = Trie.root_hash(trie)
      trie = Trie.delete(trie, "other")
      assert Trie.root_hash(trie) == hash_before
    end

    test "delete one of multiple keys" do
      trie = Trie.new()
      trie = Trie.put(trie, "key1", "val1")
      trie = Trie.put(trie, "key2", "val2")
      trie = Trie.delete(trie, "key1")

      assert {:ok, nil} = Trie.get(trie, "key1")
      assert {:ok, "val2"} = Trie.get(trie, "key2")
    end

    test "root hash matches after delete-rebuild" do
      # Build trie with only key2 directly
      trie_direct = Trie.new() |> Trie.put("key2", "val2")

      # Build trie with key1+key2, then delete key1
      trie_indirect =
        Trie.new()
        |> Trie.put("key1", "val1")
        |> Trie.put("key2", "val2")
        |> Trie.delete("key1")

      assert Trie.root_hash(trie_direct) == Trie.root_hash(trie_indirect)
    end
  end

  describe "root hash changes on modification" do
    test "each insert changes root hash" do
      trie0 = Trie.new()
      hash0 = Trie.root_hash(trie0)

      trie1 = Trie.put(trie0, "a", "1")
      hash1 = Trie.root_hash(trie1)

      trie2 = Trie.put(trie1, "b", "2")
      hash2 = Trie.root_hash(trie2)

      assert hash0 != hash1
      assert hash1 != hash2
      assert hash0 != hash2
    end

    test "update changes root hash" do
      trie = Trie.new() |> Trie.put("key", "val1")
      hash1 = Trie.root_hash(trie)
      trie = Trie.put(trie, "key", "val2")
      hash2 = Trie.root_hash(trie)
      assert hash1 != hash2
    end
  end

  describe "Ethereum test vectors" do
    # From ethereum/tests: TrieTests/trietest.json
    test "single-entry trie (do -> verb)" do
      trie = Trie.new()
      trie = Trie.put(trie, "do", "verb")

      # The root hash should be deterministic
      hash = Trie.root_hash(trie)
      assert byte_size(hash) == 32
      assert {:ok, "verb"} = Trie.get(trie, "do")
    end

    test "puppy test vector" do
      trie =
        Trie.new()
        |> Trie.put("do", "verb")
        |> Trie.put("dog", "puppy")
        |> Trie.put("doge", "coin")
        |> Trie.put("horse", "stallion")

      assert {:ok, "verb"} = Trie.get(trie, "do")
      assert {:ok, "puppy"} = Trie.get(trie, "dog")
      assert {:ok, "coin"} = Trie.get(trie, "doge")
      assert {:ok, "stallion"} = Trie.get(trie, "horse")

      hash = Trie.root_hash(trie)
      assert byte_size(hash) == 32

      # Verify determinism: same entries in different order yield same root
      trie2 =
        Trie.new()
        |> Trie.put("horse", "stallion")
        |> Trie.put("doge", "coin")
        |> Trie.put("do", "verb")
        |> Trie.put("dog", "puppy")

      assert Trie.root_hash(trie2) == hash
    end
  end
end
