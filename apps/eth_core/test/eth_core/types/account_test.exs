defmodule EthCore.Types.AccountTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Account

  describe "new/0" do
    test "creates empty account" do
      account = Account.new()
      assert account.nonce == 0
      assert account.balance == 0
      assert account.storage_root == Account.empty_trie_root()
      assert account.code_hash == Account.empty_code_hash()
    end
  end

  describe "new/1" do
    test "creates account with balance" do
      account = Account.new(1_000_000)
      assert account.balance == 1_000_000
      assert account.nonce == 0
    end
  end

  describe "empty?/1" do
    test "new account is empty" do
      assert Account.empty?(Account.new())
    end

    test "account with balance is not empty" do
      refute Account.empty?(Account.new(1))
    end

    test "account with nonce is not empty" do
      refute Account.empty?(%Account{nonce: 1})
    end
  end

  describe "empty_trie_root/0" do
    test "matches known value" do
      # keccak256(RLP("")) = keccak256(0x80)
      expected =
        Base.decode16!("56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421",
          case: :upper
        )

      assert Account.empty_trie_root() == expected
    end
  end

  describe "empty_code_hash/0" do
    test "is keccak256 of empty bytes" do
      assert Account.empty_code_hash() == EthCrypto.Hash.keccak256(<<>>)
    end
  end
end
