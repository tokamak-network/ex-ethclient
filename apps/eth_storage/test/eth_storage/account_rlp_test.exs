defmodule EthStorage.AccountRLPTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Account
  alias EthStorage.AccountRLP

  describe "encode/1" do
    test "encodes an empty account" do
      account = Account.new()
      encoded = AccountRLP.encode(account)

      assert is_binary(encoded)
      # Should be decodable RLP
      decoded = ExRLP.decode(encoded)
      assert length(decoded) == 4
    end

    test "encodes an account with balance" do
      account = %Account{
        nonce: 0,
        balance: 1_000_000,
        storage_root: Account.empty_trie_root(),
        code_hash: Account.empty_code_hash()
      }

      encoded = AccountRLP.encode(account)
      [nonce_bin, balance_bin, storage_root, code_hash] = ExRLP.decode(encoded)

      assert nonce_bin == <<>>
      assert :binary.decode_unsigned(balance_bin) == 1_000_000
      assert storage_root == Account.empty_trie_root()
      assert code_hash == Account.empty_code_hash()
    end

    test "encodes nonce as minimal big-endian binary" do
      account = %Account{Account.new() | nonce: 256}
      encoded = AccountRLP.encode(account)
      [nonce_bin | _] = ExRLP.decode(encoded)

      assert nonce_bin == <<1, 0>>
    end
  end

  describe "decode/1" do
    test "decodes an RLP-encoded empty account" do
      account = Account.new()
      encoded = AccountRLP.encode(account)

      assert {:ok, decoded} = AccountRLP.decode(encoded)
      assert decoded.nonce == 0
      assert decoded.balance == 0
      assert decoded.storage_root == Account.empty_trie_root()
      assert decoded.code_hash == Account.empty_code_hash()
    end

    test "returns error for invalid RLP" do
      assert {:error, _} = AccountRLP.decode(<<0xFF, 0xFF>>)
    end
  end

  describe "encode/decode roundtrip" do
    test "roundtrips an empty account" do
      account = Account.new()
      assert {:ok, decoded} = account |> AccountRLP.encode() |> AccountRLP.decode()
      assert decoded.nonce == account.nonce
      assert decoded.balance == account.balance
      assert decoded.storage_root == account.storage_root
      assert decoded.code_hash == account.code_hash
    end

    test "roundtrips an account with nonce and balance" do
      account = %Account{
        nonce: 42,
        balance: 10_000_000_000_000_000_000,
        storage_root: Account.empty_trie_root(),
        code_hash: Account.empty_code_hash()
      }

      assert {:ok, decoded} = account |> AccountRLP.encode() |> AccountRLP.decode()
      assert decoded.nonce == 42
      assert decoded.balance == 10_000_000_000_000_000_000
    end

    test "roundtrips an account with custom hashes" do
      storage_root = EthCrypto.Hash.keccak256("storage")
      code_hash = EthCrypto.Hash.keccak256("code")

      account = %Account{
        nonce: 1,
        balance: 500,
        storage_root: storage_root,
        code_hash: code_hash
      }

      assert {:ok, decoded} = account |> AccountRLP.encode() |> AccountRLP.decode()
      assert decoded.storage_root == storage_root
      assert decoded.code_hash == code_hash
    end
  end
end
