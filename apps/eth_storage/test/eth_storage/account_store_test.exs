defmodule EthStorage.AccountStoreTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Account
  alias EthStorage.{AccountStore, Store}

  defp start_store(_context) do
    name = :"test_store_#{System.unique_integer([:positive])}"
    store = start_supervised!({Store, name: name})
    %{store: store}
  end

  defp sample_address,
    do: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20>>

  setup [:start_store]

  describe "put_account/3 and get_account/2" do
    test "stores and retrieves an account", %{store: store} do
      address = sample_address()
      account = %Account{nonce: 1, balance: 1_000_000}

      assert :ok = AccountStore.put_account(address, account, store)
      assert {:ok, retrieved} = AccountStore.get_account(address, store)

      assert retrieved.nonce == 1
      assert retrieved.balance == 1_000_000
    end

    test "returns nil for non-existent account", %{store: store} do
      address = <<0::160>>
      assert {:ok, nil} = AccountStore.get_account(address, store)
    end

    test "updates existing account", %{store: store} do
      address = sample_address()

      :ok = AccountStore.put_account(address, %Account{nonce: 0, balance: 100}, store)
      :ok = AccountStore.put_account(address, %Account{nonce: 1, balance: 200}, store)

      {:ok, account} = AccountStore.get_account(address, store)
      assert account.nonce == 1
      assert account.balance == 200
    end

    test "different addresses have separate accounts", %{store: store} do
      addr1 = <<1::160>>
      addr2 = <<2::160>>

      :ok = AccountStore.put_account(addr1, Account.new(100), store)
      :ok = AccountStore.put_account(addr2, Account.new(200), store)

      {:ok, a1} = AccountStore.get_account(addr1, store)
      {:ok, a2} = AccountStore.get_account(addr2, store)

      assert a1.balance == 100
      assert a2.balance == 200
    end

    test "preserves empty account fields", %{store: store} do
      address = sample_address()
      account = Account.new()

      :ok = AccountStore.put_account(address, account, store)
      {:ok, retrieved} = AccountStore.get_account(address, store)

      assert retrieved.nonce == 0
      assert retrieved.balance == 0
      assert retrieved.storage_root == Account.empty_trie_root()
      assert retrieved.code_hash == Account.empty_code_hash()
    end
  end

  describe "get_code/2" do
    test "returns nil for non-existent code hash", %{store: store} do
      assert {:ok, nil} = AccountStore.get_code(<<0::256>>, store)
    end

    test "returns stored code", %{store: store} do
      code_hash = EthCrypto.Hash.keccak256(<<1, 2, 3>>)
      :ok = Store.put_account_code(store, code_hash, <<1, 2, 3>>)

      assert {:ok, <<1, 2, 3>>} = AccountStore.get_code(code_hash, store)
    end
  end

  describe "get_storage/3" do
    test "returns nil for non-existent storage slot", %{store: store} do
      address = sample_address()
      slot = <<0::256>>
      assert {:ok, nil} = AccountStore.get_storage(address, slot, store)
    end
  end
end
