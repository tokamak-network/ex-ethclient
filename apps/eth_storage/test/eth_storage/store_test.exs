defmodule EthStorage.StoreTest do
  use ExUnit.Case, async: true

  alias EthStorage.Store

  setup do
    name = :"store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Store.start_link(name: name)
    %{store: name, pid: pid}
  end

  describe "block headers" do
    test "put and get block header", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      header = "rlp_encoded_header"
      assert :ok = Store.put_block_header(store, hash, header)
      assert {:ok, ^header} = Store.get_block_header(store, hash)
    end

    test "returns nil for missing header", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert {:ok, nil} = Store.get_block_header(store, hash)
    end
  end

  describe "block bodies" do
    test "put and get block body", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      body = "rlp_encoded_body"
      assert :ok = Store.put_block_body(store, hash, body)
      assert {:ok, ^body} = Store.get_block_body(store, hash)
    end
  end

  describe "canonical hashes" do
    test "set and get canonical hash", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert :ok = Store.set_canonical_hash(store, 42, hash)
      assert {:ok, ^hash} = Store.get_canonical_hash(store, 42)
    end

    test "returns nil for missing number", %{store: store} do
      assert {:ok, nil} = Store.get_canonical_hash(store, 999)
    end
  end

  describe "get_block_by_number/2" do
    test "returns header and body for stored block", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      header = "header_data"
      body = "body_data"

      :ok = Store.set_canonical_hash(store, 1, hash)
      :ok = Store.put_block_header(store, hash, header)
      :ok = Store.put_block_body(store, hash, body)

      assert {:ok, {^header, ^body}} = Store.get_block_by_number(store, 1)
    end

    test "returns nil for missing block number", %{store: store} do
      assert {:ok, nil} = Store.get_block_by_number(store, 999)
    end
  end

  describe "latest block number" do
    test "set and get latest block number", %{store: store} do
      assert :ok = Store.set_latest_block_number(store, 100)
      assert {:ok, 100} = Store.get_latest_block_number(store)
    end

    test "returns nil when not set", %{store: store} do
      assert {:ok, nil} = Store.get_latest_block_number(store)
    end
  end

  describe "accounts" do
    test "put and get account", %{store: store} do
      addr_hash = :crypto.strong_rand_bytes(32)
      account = "encoded_account"
      assert :ok = Store.put_account(store, addr_hash, account)
      assert {:ok, ^account} = Store.get_account(store, addr_hash)
    end
  end

  describe "account codes" do
    test "put and get account code", %{store: store} do
      code_hash = :crypto.strong_rand_bytes(32)
      code = "bytecode_here"
      assert :ok = Store.put_account_code(store, code_hash, code)
      assert {:ok, ^code} = Store.get_account_code(store, code_hash)
    end
  end

  describe "receipts" do
    test "put and get receipt", %{store: store} do
      block_hash = :crypto.strong_rand_bytes(32)
      receipt = "encoded_receipt"
      assert :ok = Store.put_receipt(store, block_hash, 0, receipt)
      assert {:ok, ^receipt} = Store.get_receipt(store, block_hash, 0)
    end

    test "different indices store independently", %{store: store} do
      block_hash = :crypto.strong_rand_bytes(32)
      :ok = Store.put_receipt(store, block_hash, 0, "receipt0")
      :ok = Store.put_receipt(store, block_hash, 1, "receipt1")
      assert {:ok, "receipt0"} = Store.get_receipt(store, block_hash, 0)
      assert {:ok, "receipt1"} = Store.get_receipt(store, block_hash, 1)
    end
  end

  describe "trie nodes" do
    test "put and get account trie node", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      data = "trie_node_data"
      assert :ok = Store.put_trie_node(store, hash, data)
      assert {:ok, ^data} = Store.get_trie_node(store, hash)
    end
  end

  describe "storage trie nodes" do
    test "put and get storage trie node", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      data = "storage_trie_data"
      assert :ok = Store.put_storage_trie_node(store, hash, data)
      assert {:ok, ^data} = Store.get_storage_trie_node(store, hash)
    end
  end
end
