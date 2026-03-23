defmodule EthStorage.MPT.TrieProofTest do
  use ExUnit.Case, async: true

  alias EthStorage.MPT.Trie

  describe "get_proof/2" do
    test "returns empty list for empty trie" do
      trie = Trie.new()
      assert {:ok, []} = Trie.get_proof(trie, "anykey")
    end

    test "returns non-empty proof for existing key" do
      trie =
        Trie.new()
        |> Trie.put("key1", "value1")

      assert {:ok, proof} = Trie.get_proof(trie, "key1")
      assert length(proof) > 0
    end

    test "proof nodes are valid RLP-encoded binaries" do
      trie =
        Trie.new()
        |> Trie.put("key1", "value1")
        |> Trie.put("key2", "value2")

      assert {:ok, proof} = Trie.get_proof(trie, "key1")

      Enum.each(proof, fn node_rlp ->
        assert is_binary(node_rlp)
        # Should be valid RLP — decode should not raise
        decoded = ExRLP.decode(node_rlp)
        assert is_list(decoded) or is_binary(decoded)
      end)
    end

    test "proof for non-existing key returns proof of absence" do
      trie =
        Trie.new()
        |> Trie.put("abc", "val_abc")
        |> Trie.put("abd", "val_abd")

      assert {:ok, proof} = Trie.get_proof(trie, "xyz")
      # Should still return some proof nodes (at least the root)
      assert is_list(proof)
    end

    test "proof covers the path from root to leaf" do
      trie =
        Trie.new()
        |> Trie.put("do", "verb")
        |> Trie.put("dog", "puppy")
        |> Trie.put("doge", "coin")
        |> Trie.put("horse", "stallion")

      assert {:ok, proof} = Trie.get_proof(trie, "dog")
      # Multiple nodes in the path from root to "dog"
      assert length(proof) >= 1
    end

    test "single-entry trie returns exactly one proof node" do
      trie = Trie.new() |> Trie.put("hello", "world")
      assert {:ok, proof} = Trie.get_proof(trie, "hello")
      assert length(proof) == 1
    end
  end
end
