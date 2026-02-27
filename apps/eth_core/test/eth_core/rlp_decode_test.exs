defmodule EthCore.RLPDecodeTest do
  use ExUnit.Case, async: true

  alias EthCore.RLP
  alias EthCore.Transaction.Signer
  alias EthCore.Types.{BlockHeader, Log, Receipt, Transaction}

  # --- Signed Transaction decode round-trips ---

  describe "decode_signed/1 - Legacy" do
    test "round-trips legacy signed transaction" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.Legacy{
        nonce: 9,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.nonce == 9
      assert decoded.tx.gas_price == 20_000_000_000
      assert decoded.tx.gas_limit == 21_000
      assert decoded.tx.to == tx.to
      assert decoded.tx.value == 1_000_000_000_000_000_000
      assert decoded.v == signed.v
      assert decoded.r == signed.r
      assert decoded.s == signed.s
    end

    test "round-trips legacy contract creation" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 100_000,
        to: nil,
        value: 0,
        data: <<0x60, 0x00>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.to == nil
      assert decoded.tx.data == <<0x60, 0x00>>
    end

    test "decoded transaction can be used for sender recovery" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected = EthCore.Types.Address.from_public_key(public_key)

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)
      {:ok, recovered} = Signer.recover_sender(decoded)
      assert recovered == expected
    end
  end

  describe "decode_signed/1 - EIP-2930" do
    test "round-trips EIP-2930 signed transaction" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.EIP2930{
        chain_id: 1,
        nonce: 5,
        gas_price: 30_000_000_000,
        gas_limit: 50_000,
        to: <<2::160>>,
        value: 100,
        data: <<0xDE, 0xAD>>,
        access_list: [{<<3::160>>, [<<1::256>>]}]
      }

      {:ok, signed} = Signer.sign(tx, private_key)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.chain_id == 1
      assert decoded.tx.nonce == 5
      assert decoded.tx.gas_price == 30_000_000_000
      assert [{addr, [key]}] = decoded.tx.access_list
      assert addr == <<3::160>>
      assert key == <<1::256>>
      assert decoded.v == signed.v
    end

    test "round-trips with empty access list" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      {:ok, signed} = Signer.sign(tx, private_key)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)
      assert decoded.tx.access_list == []
    end
  end

  describe "decode_signed/1 - EIP-1559" do
    test "round-trips EIP-1559 signed transaction" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 42,
        max_priority_fee_per_gas: 2_000_000_000,
        max_fee_per_gas: 50_000_000_000,
        gas_limit: 100_000,
        to: <<5::160>>,
        value: 0,
        data: <<0xCA, 0xFE>>,
        access_list: []
      }

      {:ok, signed} = Signer.sign(tx, private_key)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.chain_id == 1
      assert decoded.tx.nonce == 42
      assert decoded.tx.max_priority_fee_per_gas == 2_000_000_000
      assert decoded.tx.max_fee_per_gas == 50_000_000_000
      assert decoded.tx.data == <<0xCA, 0xFE>>
      assert decoded.tx.access_list == []
    end
  end

  describe "decode_signed/1 - error cases" do
    test "empty data returns error" do
      assert {:error, :empty_data} = RLP.decode_signed(<<>>)
    end

    test "unknown type byte returns error" do
      # type 5 with a valid empty-list RLP body
      assert {:error, {:unknown_tx_type, 5}} = RLP.decode_signed(<<5, 0xC0>>)
    end

    test "type byte 0 (not a valid typed tx) returns error" do
      assert {:error, :invalid_transaction_data} = RLP.decode_signed(<<0>>)
    end

    test "single byte in invalid range returns error" do
      # 0x80-0xBF range: not a list, not a typed tx
      assert {:error, :invalid_transaction_data} = RLP.decode_signed(<<0x80>>)
    end

    test "truncated typed tx data returns error" do
      assert {:error, _} = RLP.decode_signed(<<1, 0xC0>>)
    end

    test "completely invalid binary returns error" do
      assert {:error, _} = RLP.decode_signed(<<0xFF, 0xFF, 0xFF>>)
    end

    test "legacy tx with wrong field count returns error" do
      # RLP list with only 3 elements (needs 9 for legacy)
      short_list = ExRLP.encode([<<>>, <<>>, <<>>])
      assert {:error, :invalid_legacy_transaction} = RLP.decode_signed(short_list)
    end

    test "typed tx with wrong field count returns error" do
      # type 2 (EIP-1559) with only 3 elements (needs 12)
      short_list = ExRLP.encode([<<>>, <<>>, <<>>])
      assert {:error, :invalid_eip1559_transaction} = RLP.decode_signed(<<2>> <> short_list)
    end

    test "malformed access list returns specific error" do
      # Valid EIP-2930 structure but with malformed access_list (not [addr, keys] pairs)
      malformed_rlp =
        ExRLP.encode([
          <<1>>,
          <<>>,
          <<>>,
          <<>>,
          <<1::160>>,
          <<>>,
          <<>>,
          # access_list: single binary instead of list of pairs
          [["not_an_address"]],
          <<>>,
          <<>>,
          <<>>
        ])

      assert {:error, _} = RLP.decode_signed(<<1>> <> malformed_rlp)
    end
  end

  # --- Block Header decode ---

  describe "decode_header/1" do
    test "round-trips 15-field base header" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 131_072,
        number: 1,
        gas_limit: 30_000_000,
        gas_used: 21_000,
        timestamp: 1_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>
      }

      encoded = RLP.encode_header(header)
      {:ok, decoded} = RLP.decode_header(encoded)

      assert decoded.difficulty == 131_072
      assert decoded.number == 1
      assert decoded.gas_limit == 30_000_000
      assert decoded.gas_used == 21_000
      assert decoded.timestamp == 1_000_000
      assert decoded.base_fee_per_gas == nil
    end

    test "round-trips 16-field post-London header" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 100,
        gas_limit: 30_000_000,
        gas_used: 15_000_000,
        timestamp: 2_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 1_000_000_000
      }

      encoded = RLP.encode_header(header)
      {:ok, decoded} = RLP.decode_header(encoded)

      assert decoded.base_fee_per_gas == 1_000_000_000
      assert decoded.withdrawals_root == nil
    end

    test "round-trips 20-field post-Cancun header" do
      header = %BlockHeader{
        parent_hash: <<1::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 1000,
        gas_limit: 30_000_000,
        gas_used: 20_000_000,
        timestamp: 3_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 2_000_000_000,
        withdrawals_root: <<2::256>>,
        blob_gas_used: 131_072,
        excess_blob_gas: 0,
        parent_beacon_block_root: <<3::256>>
      }

      encoded = RLP.encode_header(header)
      {:ok, decoded} = RLP.decode_header(encoded)

      assert decoded.base_fee_per_gas == 2_000_000_000
      assert decoded.withdrawals_root == <<2::256>>
      assert decoded.blob_gas_used == 131_072
      assert decoded.excess_blob_gas == 0
      assert decoded.parent_beacon_block_root == <<3::256>>
      assert decoded.requests_hash == nil
    end

    test "round-trips 21-field post-Prague header" do
      header = %BlockHeader{
        parent_hash: <<1::256>>,
        ommers_hash: <<0::256>>,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 2000,
        gas_limit: 30_000_000,
        gas_used: 25_000_000,
        timestamp: 4_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 3_000_000_000,
        withdrawals_root: <<2::256>>,
        blob_gas_used: 262_144,
        excess_blob_gas: 131_072,
        parent_beacon_block_root: <<3::256>>,
        requests_hash: <<4::256>>
      }

      encoded = RLP.encode_header(header)
      {:ok, decoded} = RLP.decode_header(encoded)

      assert decoded.requests_hash == <<4::256>>
    end

    test "invalid RLP returns error" do
      assert {:error, :invalid_rlp} = RLP.decode_header(<<0xFF, 0xFF>>)
    end

    test "too few fields returns error" do
      # Only 10 fields (needs at least 15)
      short = ExRLP.encode([<<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>, <<>>])
      assert {:error, :invalid_header} = RLP.decode_header(short)
    end

    test "non-list RLP returns error" do
      # Single binary, not a list
      assert {:error, :invalid_header} = RLP.decode_header(ExRLP.encode("not a list"))
    end
  end

  # --- Receipt encode/decode ---

  describe "encode_receipt/1 and decode_receipt/1" do
    test "round-trips legacy receipt (type 0)" do
      receipt = %Receipt{
        type: 0,
        status: 1,
        cumulative_gas_used: 21_000,
        logs_bloom: <<0::2048>>,
        logs: [
          %Log{
            address: <<1::160>>,
            topics: [<<100::256>>],
            data: <<0xDE, 0xAD>>
          }
        ]
      }

      encoded = RLP.encode_receipt(receipt)
      {:ok, decoded} = RLP.decode_receipt(encoded)

      assert decoded.type == 0
      assert decoded.status == 1
      assert decoded.cumulative_gas_used == 21_000
      assert length(decoded.logs) == 1
      [log] = decoded.logs
      assert log.address == <<1::160>>
      assert log.topics == [<<100::256>>]
      assert log.data == <<0xDE, 0xAD>>
    end

    test "round-trips typed receipt (type 2)" do
      receipt = %Receipt{
        type: 2,
        status: 0,
        cumulative_gas_used: 42_000,
        logs_bloom: <<0::2048>>,
        logs: []
      }

      encoded = RLP.encode_receipt(receipt)
      assert <<2, _::binary>> = encoded
      {:ok, decoded} = RLP.decode_receipt(encoded)

      assert decoded.type == 2
      assert decoded.status == 0
      assert decoded.cumulative_gas_used == 42_000
      assert decoded.logs == []
    end

    test "round-trips receipt with multiple logs" do
      receipt = %Receipt{
        type: 1,
        status: 1,
        cumulative_gas_used: 100_000,
        logs_bloom: <<0::2048>>,
        logs: [
          %Log{address: <<1::160>>, topics: [], data: <<>>},
          %Log{address: <<2::160>>, topics: [<<1::256>>, <<2::256>>], data: <<0xFF>>}
        ]
      }

      encoded = RLP.encode_receipt(receipt)
      {:ok, decoded} = RLP.decode_receipt(encoded)

      assert length(decoded.logs) == 2
      [log1, log2] = decoded.logs
      assert log1.address == <<1::160>>
      assert log2.topics == [<<1::256>>, <<2::256>>]
    end

    test "round-trips type 3 (blob) receipt" do
      receipt = %Receipt{
        type: 3,
        status: 1,
        cumulative_gas_used: 131_072,
        logs_bloom: <<0::2048>>,
        logs: []
      }

      encoded = RLP.encode_receipt(receipt)
      assert <<3, _::binary>> = encoded
      {:ok, decoded} = RLP.decode_receipt(encoded)
      assert decoded.type == 3
    end

    test "round-trips type 4 (set-code) receipt" do
      receipt = %Receipt{
        type: 4,
        status: 1,
        cumulative_gas_used: 50_000,
        logs_bloom: <<0::2048>>,
        logs: []
      }

      encoded = RLP.encode_receipt(receipt)
      assert <<4, _::binary>> = encoded
      {:ok, decoded} = RLP.decode_receipt(encoded)
      assert decoded.type == 4
    end

    test "invalid receipt data returns error" do
      assert {:error, :invalid_receipt} = RLP.decode_receipt(<<>>)
      assert {:error, :invalid_receipt} = RLP.decode_receipt(<<0x50>>)
    end
  end
end
