defmodule EthStorage.EncodingTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.{Account, BlockHeader}
  alias EthStorage.Encoding

  defp sample_header do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<1::256>>,
      coinbase: <<0::160>>,
      state_root: <<2::256>>,
      transactions_root: <<3::256>>,
      receipts_root: <<4::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 1000,
      number: 42,
      gas_limit: 8_000_000,
      gas_used: 500_000,
      timestamp: 1_600_000_000,
      extra_data: <<>>,
      mix_hash: <<5::256>>,
      nonce: <<0, 0, 0, 0, 0, 0, 0, 1>>
    }
  end

  describe "encode_header/1 and decode_header/1" do
    test "roundtrip preserves header" do
      header = sample_header()
      encoded = Encoding.encode_header(header)
      assert {:ok, decoded} = Encoding.decode_header(encoded)
      assert decoded == header
    end

    test "roundtrip with optional fields" do
      header = %{sample_header() | base_fee_per_gas: 1_000_000_000}
      encoded = Encoding.encode_header(header)
      assert {:ok, decoded} = Encoding.decode_header(encoded)
      assert decoded.base_fee_per_gas == 1_000_000_000
    end

    test "decode_header returns error for invalid binary" do
      assert {:error, :decode_error} = Encoding.decode_header(<<0, 1, 2, 3>>)
    end

    test "decode_header returns error for non-header term" do
      encoded = :erlang.term_to_binary(%{not: :a_header})
      assert {:error, :invalid_header} = Encoding.decode_header(encoded)
    end
  end

  describe "encode_body/3 and decode_body/1" do
    test "roundtrip with empty body" do
      encoded = Encoding.encode_body([], [], nil)
      assert {:ok, body} = Encoding.decode_body(encoded)
      assert body.transactions == []
      assert body.ommers == []
      assert is_nil(body.withdrawals)
    end

    test "roundtrip preserves transactions list" do
      txs = [:tx1, :tx2]
      encoded = Encoding.encode_body(txs, [], nil)
      assert {:ok, body} = Encoding.decode_body(encoded)
      assert body.transactions == txs
    end

    test "decode_body returns error for invalid binary" do
      assert {:error, :decode_error} = Encoding.decode_body(<<0, 1, 2>>)
    end

    test "decode_body returns error for non-body term" do
      encoded = :erlang.term_to_binary(%{wrong: :format})
      assert {:error, :invalid_body} = Encoding.decode_body(encoded)
    end
  end

  describe "encode_account/1 and decode_account/1" do
    test "roundtrip preserves account" do
      account = %Account{nonce: 5, balance: 1_000_000}
      encoded = Encoding.encode_account(account)
      assert {:ok, decoded} = Encoding.decode_account(encoded)
      assert decoded.nonce == 5
      assert decoded.balance == 1_000_000
      assert decoded.storage_root == Account.empty_trie_root()
      assert decoded.code_hash == Account.empty_code_hash()
    end

    test "roundtrip preserves empty account" do
      account = Account.new()
      encoded = Encoding.encode_account(account)
      assert {:ok, decoded} = Encoding.decode_account(encoded)
      assert decoded == account
    end

    test "decode_account returns error for invalid binary" do
      assert {:error, :decode_error} = Encoding.decode_account(<<0>>)
    end

    test "decode_account returns error for non-account term" do
      encoded = :erlang.term_to_binary(:not_an_account)
      assert {:error, :invalid_account} = Encoding.decode_account(encoded)
    end
  end

  describe "block_hash/1" do
    test "returns 32-byte binary" do
      hash = Encoding.block_hash(sample_header())
      assert byte_size(hash) == 32
    end

    test "is deterministic" do
      header = sample_header()
      assert Encoding.block_hash(header) == Encoding.block_hash(header)
    end

    test "different headers produce different hashes" do
      h1 = sample_header()
      h2 = %{h1 | number: 99}
      refute Encoding.block_hash(h1) == Encoding.block_hash(h2)
    end
  end
end
