defmodule EthCore.Types.AccountTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Account

  # keccak256("") — empty code hash per EIP-161
  @empty_code_hash Base.decode16!(
                     "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
                     case: :lower
                   )

  # keccak256(RLP("")) = keccak256(0x80) — empty trie root
  @empty_trie_hash Base.decode16!(
                     "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
                     case: :lower
                   )

  describe "new/0" do
    test "default account has zero balance and nonce" do
      account = Account.new()
      assert account.nonce == 0
      assert account.balance == 0
    end

    test "default account has empty code hash" do
      account = Account.new()
      assert account.code_hash == @empty_code_hash
    end

    test "default account has empty storage root" do
      account = Account.new()
      assert account.storage_root == @empty_trie_hash
    end
  end

  describe "new/1" do
    test "creates account with custom balance" do
      account = Account.new(balance: 1_000_000)
      assert account.balance == 1_000_000
      assert account.nonce == 0
    end

    test "creates account with custom nonce and balance" do
      account = Account.new(nonce: 5, balance: 100)
      assert account.nonce == 5
      assert account.balance == 100
    end
  end

  describe "empty?/1" do
    test "default account is empty (EIP-161)" do
      assert Account.empty?(Account.new())
    end

    test "account with balance is not empty" do
      refute Account.empty?(Account.new(balance: 1))
    end

    test "account with nonce is not empty" do
      refute Account.empty?(Account.new(nonce: 1))
    end

    test "account with code is not empty" do
      code_hash = EthCrypto.Hash.keccak256("some code")
      account = %Account{Account.new() | code_hash: code_hash}
      refute Account.empty?(account)
    end
  end

  describe "has_code?/1" do
    test "default account has no code" do
      refute Account.has_code?(Account.new())
    end

    test "account with non-empty code hash has code" do
      code_hash = EthCrypto.Hash.keccak256("contract bytecode")
      account = %Account{Account.new() | code_hash: code_hash}
      assert Account.has_code?(account)
    end
  end
end
