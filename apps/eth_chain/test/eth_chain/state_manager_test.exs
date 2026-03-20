defmodule EthChain.StateManagerTest do
  use ExUnit.Case, async: false

  alias EthChain.StateManager
  alias EthCore.Types.Account
  alias EthStorage.MPT.Trie

  setup do
    {:ok, store} = EthStorage.Store.start_link(name: :"store_#{:erlang.unique_integer()}")
    {:ok, store: store}
  end

  describe "state_root/1" do
    test "empty state has empty trie root" do
      trie = Trie.new()
      assert StateManager.state_root(trie) == Trie.empty_root_hash()
    end
  end

  describe "get_account/2" do
    test "returns nil for non-existent account" do
      trie = Trie.new()
      address = <<1::160>>
      assert {:ok, nil} = StateManager.get_account(trie, address)
    end
  end

  describe "apply_account_updates/3" do
    test "applies a single new account with balance", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>

      updates = %{
        address => %{nonce: 0, balance: 1_000_000, code: nil, storage: %{}}
      }

      assert {:ok, new_trie, root} =
               StateManager.apply_account_updates(trie, updates, store)

      assert root != Trie.empty_root_hash()
      assert byte_size(root) == 32

      # Verify the account is stored
      assert {:ok, account} = StateManager.get_account(new_trie, address)
      assert account.balance == 1_000_000
      assert account.nonce == 0
    end

    test "applies multiple account updates", %{store: store} do
      trie = Trie.new()
      addr1 = <<1::160>>
      addr2 = <<2::160>>

      updates = %{
        addr1 => %{nonce: 1, balance: 100, code: nil, storage: %{}},
        addr2 => %{nonce: 0, balance: 200, code: nil, storage: %{}}
      }

      assert {:ok, new_trie, _root} =
               StateManager.apply_account_updates(trie, updates, store)

      assert {:ok, acct1} = StateManager.get_account(new_trie, addr1)
      assert acct1.balance == 100
      assert acct1.nonce == 1

      assert {:ok, acct2} = StateManager.get_account(new_trie, addr2)
      assert acct2.balance == 200
    end

    test "updates an existing account", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>

      initial = %{address => %{nonce: 0, balance: 100, code: nil, storage: %{}}}

      assert {:ok, trie1, root1} =
               StateManager.apply_account_updates(trie, initial, store)

      update = %{address => %{nonce: 1, balance: 50, code: nil, storage: %{}}}

      assert {:ok, trie2, root2} =
               StateManager.apply_account_updates(trie1, update, store)

      assert root1 != root2

      assert {:ok, account} = StateManager.get_account(trie2, address)
      assert account.balance == 50
      assert account.nonce == 1
    end

    test "account with code stores code and updates code_hash", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>
      code = <<0x60, 0x00, 0x60, 0x00, 0xF3>>

      updates = %{
        address => %{nonce: 0, balance: 0, code: code, storage: %{}}
      }

      assert {:ok, new_trie, _root} =
               StateManager.apply_account_updates(trie, updates, store)

      assert {:ok, account} = StateManager.get_account(new_trie, address)
      expected_hash = EthCrypto.Hash.keccak256(code)
      assert account.code_hash == expected_hash

      # Verify code is stored in the store
      assert {:ok, ^code} = EthStorage.Store.get_account_code(store, expected_hash)
    end

    test "account with storage updates changes storage_root", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>

      updates = %{
        address => %{
          nonce: 0,
          balance: 0,
          code: nil,
          storage: %{<<1::256>> => <<42::256>>}
        }
      }

      assert {:ok, new_trie, _root} =
               StateManager.apply_account_updates(trie, updates, store)

      assert {:ok, account} = StateManager.get_account(new_trie, address)
      assert account.storage_root != Account.empty_trie_root()
    end

    test "state root changes when state changes", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>

      updates1 = %{address => %{nonce: 0, balance: 100, code: nil, storage: %{}}}
      updates2 = %{address => %{nonce: 0, balance: 200, code: nil, storage: %{}}}

      assert {:ok, _, root1} = StateManager.apply_account_updates(trie, updates1, store)
      assert {:ok, _, root2} = StateManager.apply_account_updates(trie, updates2, store)

      assert root1 != root2
    end

    test "state root is deterministic", %{store: store} do
      trie = Trie.new()
      address = <<1::160>>

      updates = %{address => %{nonce: 5, balance: 999, code: nil, storage: %{}}}

      assert {:ok, _, root1} = StateManager.apply_account_updates(trie, updates, store)
      assert {:ok, _, root2} = StateManager.apply_account_updates(trie, updates, store)

      assert root1 == root2
    end

    test "empty updates return empty trie root", %{store: store} do
      trie = Trie.new()

      assert {:ok, _, root} = StateManager.apply_account_updates(trie, %{}, store)
      assert root == Trie.empty_root_hash()
    end
  end
end
