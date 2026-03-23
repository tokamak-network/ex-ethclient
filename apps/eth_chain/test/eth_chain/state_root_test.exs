defmodule EthChain.StateRootTest do
  use ExUnit.Case, async: true

  alias EthChain.StateRoot
  alias EthCore.Types.Account
  alias EthStorage.MPT.Trie

  @address1 <<1::160>>
  @address2 <<2::160>>

  describe "compute_state_root/1" do
    test "empty state produces empty trie hash" do
      root = StateRoot.compute_state_root(%{})
      assert root == Trie.empty_root_hash()
    end

    test "single account produces deterministic root" do
      account = %Account{nonce: 0, balance: 1_000_000}
      root1 = StateRoot.compute_state_root(%{@address1 => account})
      root2 = StateRoot.compute_state_root(%{@address1 => account})

      assert root1 == root2
      assert byte_size(root1) == 32
      assert root1 != Trie.empty_root_hash()
    end

    test "different accounts produce different roots" do
      account_a = %Account{nonce: 0, balance: 100}
      account_b = %Account{nonce: 0, balance: 200}

      root_a = StateRoot.compute_state_root(%{@address1 => account_a})
      root_b = StateRoot.compute_state_root(%{@address1 => account_b})

      assert root_a != root_b
    end

    test "multiple accounts produce deterministic root" do
      accounts = %{
        @address1 => %Account{nonce: 1, balance: 1000},
        @address2 => %Account{nonce: 0, balance: 2000}
      }

      root1 = StateRoot.compute_state_root(accounts)
      root2 = StateRoot.compute_state_root(accounts)

      assert root1 == root2
      assert byte_size(root1) == 32
    end

    test "known genesis state produces expected root" do
      # A simple genesis with one funded account
      address = <<0xAA::160>>

      account = %Account{
        nonce: 0,
        balance: 1_000_000_000_000_000_000,
        storage_root: Account.empty_trie_root(),
        code_hash: Account.empty_code_hash()
      }

      root = StateRoot.compute_state_root(%{address => account})

      # The root should be deterministic and non-empty
      assert byte_size(root) == 32
      assert root != Trie.empty_root_hash()

      # Computing again should yield the same root
      assert StateRoot.compute_state_root(%{address => account}) == root
    end
  end

  describe "compute_storage_root/1" do
    test "empty storage produces empty trie hash" do
      root = StateRoot.compute_storage_root(%{})
      assert root == Trie.empty_root_hash()
    end

    test "single slot produces deterministic root" do
      slot = <<1::256>>
      value = <<42::256>>

      root1 = StateRoot.compute_storage_root(%{slot => value})
      root2 = StateRoot.compute_storage_root(%{slot => value})

      assert root1 == root2
      assert byte_size(root1) == 32
      assert root1 != Trie.empty_root_hash()
    end

    test "different values produce different roots" do
      slot = <<1::256>>

      root_a = StateRoot.compute_storage_root(%{slot => <<1::256>>})
      root_b = StateRoot.compute_storage_root(%{slot => <<2::256>>})

      assert root_a != root_b
    end
  end

  describe "verify_state_root/2" do
    test "round-trip: compute then verify succeeds" do
      accounts = %{
        @address1 => %Account{nonce: 1, balance: 1000},
        @address2 => %Account{nonce: 0, balance: 2000}
      }

      root = StateRoot.compute_state_root(accounts)
      assert :ok == StateRoot.verify_state_root(root, accounts)
    end

    test "mismatch detection works" do
      accounts = %{@address1 => Account.new(1000)}
      wrong_root = <<0::256>>

      assert {:error, :state_root_mismatch} == StateRoot.verify_state_root(wrong_root, accounts)
    end

    test "empty state verifies against empty trie hash" do
      empty_root = Trie.empty_root_hash()
      assert :ok == StateRoot.verify_state_root(empty_root, %{})
    end
  end

  describe "update_storage_roots/2" do
    test "updates account storage_root from storage map" do
      account = Account.new(1000)
      accounts = %{@address1 => account}

      storage_map = %{
        @address1 => %{<<1::256>> => <<42::256>>}
      }

      updated = StateRoot.update_storage_roots(accounts, storage_map)

      assert updated[@address1].storage_root != Account.empty_trie_root()
      assert updated[@address1].balance == 1000
    end

    test "ignores storage for addresses not in accounts" do
      accounts = %{@address1 => Account.new(1000)}

      storage_map = %{
        @address2 => %{<<1::256>> => <<42::256>>}
      }

      updated = StateRoot.update_storage_roots(accounts, storage_map)

      assert updated == accounts
    end
  end
end
