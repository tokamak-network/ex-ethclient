defmodule EthCore.RLPTest do
  use ExUnit.Case, async: true

  alias EthCore.RLP
  alias EthCore.Types.{Account, BlockHeader, Transaction, Withdrawal}

  # Ethereum official RLP test vectors from
  # https://github.com/ethereum/tests/blob/develop/RLPTests/rlptest.json

  describe "RLP encoding - official test vectors" do
    test "empty string" do
      assert RLP.encode(<<>>) == <<0x80>>
    end

    test "single byte (low range)" do
      assert RLP.encode(<<0x00>>) == <<0x00>>
      assert RLP.encode(<<0x7F>>) == <<0x7F>>
    end

    test "short string (1-55 bytes)" do
      assert RLP.encode("dog") == <<0x83, ?d, ?o, ?g>>
    end

    test "empty list" do
      assert RLP.encode([]) == <<0xC0>>
    end

    test "string list" do
      # ["cat", "dog"]
      encoded = RLP.encode(["cat", "dog"])
      assert encoded == <<0xC8, 0x83, ?c, ?a, ?t, 0x83, ?d, ?o, ?g>>
    end

    test "nested list" do
      # [[], [[]], [[], [[]]]]
      encoded = RLP.encode([[], [[]], [[], [[]]]])
      assert encoded == <<0xC7, 0xC0, 0xC1, 0xC0, 0xC3, 0xC0, 0xC1, 0xC0>>
    end

    test "integer encoding" do
      assert RLP.encode(<<>>) == <<0x80>>
      assert RLP.encode(<<0x0F>>) == <<0x0F>>
      assert RLP.encode(<<0x04, 0x00>>) == <<0x82, 0x04, 0x00>>
    end

    test "medium string (lorem ipsum)" do
      s =
        "Lorem ipsum dolor sit amet, consectetur adipisicing elit"

      encoded = RLP.encode(s)
      # length 56 -> 0xB8 (0xB7 + 1 length byte), 0x38 (56)
      assert <<0xB8, 56, rest::binary>> = encoded
      assert rest == s
    end

    test "long list" do
      list = [
        "asdf",
        "qwer",
        "zxcv",
        "asdf",
        "qwer",
        "zxcv",
        "asdf",
        "qwer",
        "zxcv",
        "asdf",
        "qwer"
      ]

      encoded = RLP.encode(list)
      assert is_binary(encoded)
      assert RLP.decode(encoded) == list
    end
  end

  describe "RLP round-trip" do
    test "encode then decode preserves data" do
      test_cases = [
        <<>>,
        "hello",
        "a",
        <<0>>,
        <<127>>,
        [],
        ["a", "b", "c"],
        [[], [[]], [[], [[]]]],
        :crypto.strong_rand_bytes(100)
      ]

      for data <- test_cases do
        assert RLP.decode(RLP.encode(data)) == data
      end
    end
  end

  describe "integer encoding helpers" do
    test "encode_integer/1" do
      assert RLP.encode_integer(0) == <<>>
      assert RLP.encode_integer(1) == <<1>>
      assert RLP.encode_integer(127) == <<127>>
      assert RLP.encode_integer(128) == <<128>>
      assert RLP.encode_integer(256) == <<1, 0>>
      assert RLP.encode_integer(1024) == <<4, 0>>
      assert RLP.encode_integer(0xFFFF) == <<0xFF, 0xFF>>
    end

    test "decode_integer/1" do
      assert RLP.decode_integer(<<>>) == 0
      assert RLP.decode_integer(<<1>>) == 1
      assert RLP.decode_integer(<<128>>) == 128
      assert RLP.decode_integer(<<1, 0>>) == 256
    end

    test "round-trip integers" do
      for n <- [0, 1, 127, 128, 255, 256, 1024, 0xFFFFFF, 0xFFFFFFFFFF] do
        assert RLP.decode_integer(RLP.encode_integer(n)) == n
      end
    end
  end

  describe "encode_for_signing/2 - Legacy" do
    test "encodes legacy transaction for EIP-155 signing" do
      tx = %Transaction.Legacy{
        nonce: 9,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      encoded = RLP.encode_for_signing(tx, 1)
      assert is_binary(encoded)
      assert byte_size(encoded) > 0

      # Should be decodable RLP
      decoded = RLP.decode(encoded)
      assert length(decoded) == 9
    end

    test "encodes legacy transaction for pre-EIP-155 signing" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 0,
        data: <<>>
      }

      encoded = RLP.encode_for_signing(tx, nil)
      decoded = RLP.decode(encoded)
      # Without chain_id: [nonce, gasPrice, gasLimit, to, value, data]
      assert length(decoded) == 6
    end
  end

  describe "encode_for_signing/2 - EIP-1559" do
    test "encodes EIP-1559 transaction with type prefix" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_500_000_000,
        max_fee_per_gas: 30_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>,
        access_list: []
      }

      encoded = RLP.encode_for_signing(tx, nil)
      # Should start with type byte 0x02
      assert <<2, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)
      assert length(decoded) == 9
    end
  end

  describe "encode_for_signing/2 - EIP-2930" do
    test "encodes EIP-2930 transaction with type prefix" do
      tx = %Transaction.EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 0,
        data: <<>>,
        access_list: []
      }

      encoded = RLP.encode_for_signing(tx, nil)
      assert <<1, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)
      assert length(decoded) == 8
    end
  end

  describe "encode_account/1" do
    test "encodes empty account" do
      encoded = RLP.encode_account(Account.new())
      assert is_binary(encoded)
      decoded = RLP.decode(encoded)
      assert length(decoded) == 4
    end
  end

  describe "encode_withdrawal/1" do
    test "encodes withdrawal" do
      w = %Withdrawal{
        index: 0,
        validator_index: 1,
        address: <<1::160>>,
        amount: 32_000_000_000
      }

      encoded = RLP.encode_withdrawal(w)
      assert is_binary(encoded)
      decoded = RLP.decode(encoded)
      assert length(decoded) == 4
    end
  end

  describe "encode_header/1" do
    test "encodes a block header" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 0,
        gas_limit: 0,
        gas_used: 0,
        timestamp: 0,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>
      }

      encoded = RLP.encode_header(header)
      assert is_binary(encoded)
      decoded = RLP.decode(encoded)
      # 15 base fields
      assert length(decoded) == 15
    end

    test "encodes post-London header with base_fee" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 1,
        gas_limit: 30_000_000,
        gas_used: 21_000,
        timestamp: 1_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 1_000_000_000
      }

      encoded = RLP.encode_header(header)
      decoded = RLP.decode(encoded)
      # 15 base + 1 (base_fee_per_gas)
      assert length(decoded) == 16
    end
  end
end
