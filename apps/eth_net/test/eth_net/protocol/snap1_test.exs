defmodule EthNet.Protocol.Snap1Test do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Snap1

  # --- GetAccountRange ---

  describe "GetAccountRange" do
    test "encode/decode round-trip" do
      root = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)

      {code, payload} = Snap1.encode_get_account_range(42, root, start_hash, limit_hash, 65536)
      assert code == Snap1.get_account_range_code()

      {:ok, decoded} = Snap1.decode_get_account_range(payload)
      assert decoded.request_id == 42
      assert decoded.root_hash == root
      assert decoded.start_hash == start_hash
      assert decoded.limit_hash == limit_hash
      assert decoded.response_bytes == 65536
    end

    test "large request_id encoded correctly" do
      root = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)
      large_id = 0xFFFFFFFFFFFFFFFF

      {_code, payload} =
        Snap1.encode_get_account_range(large_id, root, start_hash, limit_hash, 1024)

      {:ok, decoded} = Snap1.decode_get_account_range(payload)
      assert decoded.request_id == large_id
    end

    test "zero request_id and response_bytes" do
      root = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)

      {_code, payload} = Snap1.encode_get_account_range(0, root, start_hash, limit_hash, 0)
      {:ok, decoded} = Snap1.decode_get_account_range(payload)
      assert decoded.request_id == 0
      assert decoded.response_bytes == 0
    end
  end

  # --- AccountRange ---

  describe "AccountRange" do
    test "encode/decode round-trip with accounts" do
      hash1 = :crypto.strong_rand_bytes(32)
      storage_root = :crypto.strong_rand_bytes(32)
      code_hash = :crypto.strong_rand_bytes(32)
      proof_node = :crypto.strong_rand_bytes(64)

      accounts = [{hash1, 5, 1_000_000, storage_root, code_hash}]
      proof = [proof_node]

      {code, payload} = Snap1.encode_account_range(1, accounts, proof)
      assert code == Snap1.account_range_code()

      {:ok, decoded} = Snap1.decode_account_range(payload)
      assert decoded.request_id == 1
      assert length(decoded.accounts) == 1

      {h, nonce, balance, sr, ch} = hd(decoded.accounts)
      assert h == hash1
      assert nonce == 5
      assert balance == 1_000_000
      assert sr == storage_root
      assert ch == code_hash
      assert decoded.proof == [proof_node]
    end

    test "encode/decode with empty accounts and proof" do
      {_code, payload} = Snap1.encode_account_range(0, [], [])
      {:ok, decoded} = Snap1.decode_account_range(payload)
      assert decoded.request_id == 0
      assert decoded.accounts == []
      assert decoded.proof == []
    end

    test "multiple accounts round-trip" do
      accounts =
        for _ <- 1..3 do
          {:crypto.strong_rand_bytes(32), 0, 0, :crypto.strong_rand_bytes(32),
           :crypto.strong_rand_bytes(32)}
        end

      {_code, payload} = Snap1.encode_account_range(99, accounts, [])
      {:ok, decoded} = Snap1.decode_account_range(payload)
      assert length(decoded.accounts) == 3
    end
  end

  # --- GetStorageRanges ---

  describe "GetStorageRanges" do
    test "encode/decode round-trip" do
      root = :crypto.strong_rand_bytes(32)
      acct1 = :crypto.strong_rand_bytes(32)
      acct2 = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)

      {code, payload} =
        Snap1.encode_get_storage_ranges(7, root, [acct1, acct2], start_hash, limit_hash, 4096)

      assert code == Snap1.get_storage_ranges_code()

      {:ok, decoded} = Snap1.decode_get_storage_ranges(payload)
      assert decoded.request_id == 7
      assert decoded.root_hash == root
      assert decoded.account_hashes == [acct1, acct2]
      assert decoded.start_hash == start_hash
      assert decoded.limit_hash == limit_hash
      assert decoded.response_bytes == 4096
    end

    test "empty account list" do
      root = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)

      {_code, payload} =
        Snap1.encode_get_storage_ranges(0, root, [], start_hash, limit_hash, 0)

      {:ok, decoded} = Snap1.decode_get_storage_ranges(payload)
      assert decoded.account_hashes == []
    end
  end

  # --- StorageRanges ---

  describe "StorageRanges" do
    test "encode/decode round-trip" do
      slot_hash = :crypto.strong_rand_bytes(32)
      slot_value = :crypto.strong_rand_bytes(32)
      proof_node = :crypto.strong_rand_bytes(48)

      slots = [[{slot_hash, slot_value}]]
      proof = [proof_node]

      {code, payload} = Snap1.encode_storage_ranges(3, slots, proof)
      assert code == Snap1.storage_ranges_code()

      {:ok, decoded} = Snap1.decode_storage_ranges(payload)
      assert decoded.request_id == 3
      assert decoded.slots == [[{slot_hash, slot_value}]]
      assert decoded.proof == [proof_node]
    end

    test "empty slots and proof" do
      {_code, payload} = Snap1.encode_storage_ranges(0, [], [])
      {:ok, decoded} = Snap1.decode_storage_ranges(payload)
      assert decoded.slots == []
      assert decoded.proof == []
    end

    test "multiple accounts with multiple slots" do
      acct1_slots = [
        {:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)},
        {:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)}
      ]

      acct2_slots = [
        {:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)}
      ]

      slots = [acct1_slots, acct2_slots]

      {_code, payload} = Snap1.encode_storage_ranges(10, slots, [])
      {:ok, decoded} = Snap1.decode_storage_ranges(payload)
      assert length(decoded.slots) == 2
      assert length(hd(decoded.slots)) == 2
      assert length(List.last(decoded.slots)) == 1
    end
  end

  # --- GetByteCodes ---

  describe "GetByteCodes" do
    test "encode/decode round-trip" do
      hash1 = :crypto.strong_rand_bytes(32)
      hash2 = :crypto.strong_rand_bytes(32)

      {code, payload} = Snap1.encode_get_byte_codes(5, [hash1, hash2], 8192)
      assert code == Snap1.get_byte_codes_code()

      {:ok, decoded} = Snap1.decode_get_byte_codes(payload)
      assert decoded.request_id == 5
      assert decoded.hashes == [hash1, hash2]
      assert decoded.response_bytes == 8192
    end

    test "empty hashes" do
      {_code, payload} = Snap1.encode_get_byte_codes(0, [], 0)
      {:ok, decoded} = Snap1.decode_get_byte_codes(payload)
      assert decoded.hashes == []
    end
  end

  # --- ByteCodes ---

  describe "ByteCodes" do
    test "encode/decode round-trip" do
      code1 = :crypto.strong_rand_bytes(100)
      code2 = :crypto.strong_rand_bytes(200)

      {msg_code, payload} = Snap1.encode_byte_codes(8, [code1, code2])
      assert msg_code == Snap1.byte_codes_code()

      {:ok, decoded} = Snap1.decode_byte_codes(payload)
      assert decoded.request_id == 8
      assert decoded.codes == [code1, code2]
    end

    test "empty codes" do
      {_code, payload} = Snap1.encode_byte_codes(0, [])
      {:ok, decoded} = Snap1.decode_byte_codes(payload)
      assert decoded.codes == []
    end
  end

  # --- GetTrieNodes ---

  describe "GetTrieNodes" do
    test "encode/decode round-trip" do
      root = :crypto.strong_rand_bytes(32)
      account_path = :crypto.strong_rand_bytes(32)
      storage_path1 = :crypto.strong_rand_bytes(32)
      storage_path2 = :crypto.strong_rand_bytes(32)

      paths = [[account_path, storage_path1, storage_path2]]

      {code, payload} = Snap1.encode_get_trie_nodes(12, root, paths, 16384)
      assert code == Snap1.get_trie_nodes_code()

      {:ok, decoded} = Snap1.decode_get_trie_nodes(payload)
      assert decoded.request_id == 12
      assert decoded.root_hash == root
      assert decoded.paths == [[account_path, storage_path1, storage_path2]]
      assert decoded.response_bytes == 16384
    end

    test "empty paths" do
      root = :crypto.strong_rand_bytes(32)

      {_code, payload} = Snap1.encode_get_trie_nodes(0, root, [], 0)
      {:ok, decoded} = Snap1.decode_get_trie_nodes(payload)
      assert decoded.paths == []
    end

    test "multiple path groups" do
      root = :crypto.strong_rand_bytes(32)
      path1 = [:crypto.strong_rand_bytes(32)]
      path2 = [:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)]

      paths = [path1, path2]

      {_code, payload} = Snap1.encode_get_trie_nodes(1, root, paths, 1024)
      {:ok, decoded} = Snap1.decode_get_trie_nodes(payload)
      assert length(decoded.paths) == 2
    end
  end

  # --- TrieNodes ---

  describe "TrieNodes" do
    test "encode/decode round-trip" do
      node1 = :crypto.strong_rand_bytes(64)
      node2 = :crypto.strong_rand_bytes(128)

      {code, payload} = Snap1.encode_trie_nodes(15, [node1, node2])
      assert code == Snap1.trie_nodes_code()

      {:ok, decoded} = Snap1.decode_trie_nodes(payload)
      assert decoded.request_id == 15
      assert decoded.nodes == [node1, node2]
    end

    test "empty nodes" do
      {_code, payload} = Snap1.encode_trie_nodes(0, [])
      {:ok, decoded} = Snap1.decode_trie_nodes(payload)
      assert decoded.nodes == []
    end
  end

  # --- Decode dispatcher ---

  describe "decode/2 dispatcher" do
    test "routes GetAccountRange correctly" do
      root = :crypto.strong_rand_bytes(32)
      start_hash = :crypto.strong_rand_bytes(32)
      limit_hash = :crypto.strong_rand_bytes(32)

      {code, payload} = Snap1.encode_get_account_range(1, root, start_hash, limit_hash, 1024)
      {:ok, {:get_account_range, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 1
    end

    test "routes AccountRange correctly" do
      hash = :crypto.strong_rand_bytes(32)
      sr = :crypto.strong_rand_bytes(32)
      ch = :crypto.strong_rand_bytes(32)

      {code, payload} = Snap1.encode_account_range(2, [{hash, 0, 100, sr, ch}], [])
      {:ok, {:account_range, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 2
    end

    test "routes GetStorageRanges correctly" do
      root = :crypto.strong_rand_bytes(32)
      sh = :crypto.strong_rand_bytes(32)
      lh = :crypto.strong_rand_bytes(32)

      {code, payload} = Snap1.encode_get_storage_ranges(3, root, [], sh, lh, 512)
      {:ok, {:get_storage_ranges, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 3
    end

    test "routes StorageRanges correctly" do
      {code, payload} = Snap1.encode_storage_ranges(4, [], [])
      {:ok, {:storage_ranges, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 4
    end

    test "routes GetByteCodes correctly" do
      {code, payload} = Snap1.encode_get_byte_codes(5, [], 0)
      {:ok, {:get_byte_codes, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 5
    end

    test "routes ByteCodes correctly" do
      {code, payload} = Snap1.encode_byte_codes(6, [<<0xDE, 0xAD>>])
      {:ok, {:byte_codes, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 6
    end

    test "routes GetTrieNodes correctly" do
      root = :crypto.strong_rand_bytes(32)
      {code, payload} = Snap1.encode_get_trie_nodes(7, root, [], 0)
      {:ok, {:get_trie_nodes, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 7
    end

    test "routes TrieNodes correctly" do
      {code, payload} = Snap1.encode_trie_nodes(8, [<<0xBE, 0xEF>>])
      {:ok, {:trie_nodes, msg}} = Snap1.decode(code, payload)
      assert msg.request_id == 8
    end

    test "returns error for unknown code" do
      assert {:error, {:unknown_snap_message, 0x08}} = Snap1.decode(0x08, <<>>)
      assert {:error, {:unknown_snap_message, 0xFF}} = Snap1.decode(0xFF, <<>>)
    end
  end

  # --- snap_message? ---

  describe "snap_message?/1" do
    test "returns true for codes 0x00-0x07" do
      for code <- 0x00..0x07 do
        assert Snap1.snap_message?(code), "expected snap_message?(#{code}) to be true"
      end
    end

    test "returns false for codes outside 0x00-0x07" do
      refute Snap1.snap_message?(0x08)
      refute Snap1.snap_message?(0x10)
      refute Snap1.snap_message?(0xFF)
    end
  end
end
