defmodule EthRpc.FormattersTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.{BlockHeader, SignedTransaction, Transaction}
  alias EthRpc.Formatters

  defp sample_header do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 42,
      gas_limit: 8_000_000,
      gas_used: 21_000,
      timestamp: 1_700_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000,
      withdrawals_root: nil,
      blob_gas_used: nil,
      excess_blob_gas: nil,
      parent_beacon_block_root: nil,
      requests_hash: nil
    }
  end

  defp make_legacy_signed_tx do
    tx = %Transaction.Legacy{
      nonce: 5,
      gas_price: 2_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 1_000_000,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, 100, 200)
  end

  defp make_eip1559_signed_tx do
    tx = %Transaction.EIP1559{
      chain_id: 1,
      nonce: 10,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas_limit: 21_000,
      to: <<2::160>>,
      value: 500_000,
      data: <<0xDE, 0xAD>>,
      access_list: []
    }

    SignedTransaction.new(tx, 0, 300, 400)
  end

  defp make_eip2930_signed_tx do
    tx = %Transaction.EIP2930{
      chain_id: 1,
      nonce: 3,
      gas_price: 1_500_000_000,
      gas_limit: 42_000,
      to: <<3::160>>,
      value: 0,
      data: <<>>,
      access_list: [{<<4::160>>, [<<5::256>>]}]
    }

    SignedTransaction.new(tx, 1, 500, 600)
  end

  describe "format_block/2" do
    test "formats block header with required fields" do
      header = sample_header()
      result = Formatters.format_block(header, false)

      assert result["number"] == "0x2a"
      assert result["gasLimit"] == "0x7a1200"
      assert result["gasUsed"] == "0x5208"
      assert result["timestamp"] == "0x6553f100"
      assert result["difficulty"] == "0x0"
      assert result["transactions"] == []
      assert result["uncles"] == []
    end

    test "includes baseFeePerGas when present" do
      header = sample_header()
      result = Formatters.format_block(header, false)

      assert result["baseFeePerGas"] == "0x3b9aca00"
    end

    test "excludes optional fields when nil" do
      header = sample_header()
      result = Formatters.format_block(header, false)

      refute Map.has_key?(result, "blobGasUsed")
      refute Map.has_key?(result, "excessBlobGas")
      refute Map.has_key?(result, "parentBeaconBlockRoot")
    end

    test "includes cancun fields when present" do
      header = %{
        sample_header()
        | blob_gas_used: 131_072,
          excess_blob_gas: 0,
          parent_beacon_block_root: <<0::256>>
      }

      result = Formatters.format_block(header, false)

      assert result["blobGasUsed"] == "0x20000"
      assert result["excessBlobGas"] == "0x0"
      assert Map.has_key?(result, "parentBeaconBlockRoot")
    end

    test "all hex values are 0x-prefixed" do
      header = sample_header()
      result = Formatters.format_block(header, false)

      for {_key, value} <- result,
          is_binary(value) do
        assert String.starts_with?(value, "0x"),
               "Expected 0x prefix, got: #{inspect(value)}"
      end
    end
  end

  describe "format_block/3 with transactions" do
    test "includes transaction hashes when full_txs is false" do
      header = sample_header()
      txs = [make_legacy_signed_tx()]
      result = Formatters.format_block(header, txs, false)

      assert length(result["transactions"]) == 1
      # Should be a hex string hash
      [tx_hash] = result["transactions"]
      assert String.starts_with?(tx_hash, "0x")
      assert byte_size(tx_hash) == 66
    end

    test "includes full transaction objects when full_txs is true" do
      header = sample_header()
      txs = [make_legacy_signed_tx(), make_eip1559_signed_tx()]
      result = Formatters.format_block(header, txs, true)

      assert length(result["transactions"]) == 2
      [tx0, tx1] = result["transactions"]

      assert is_map(tx0)
      assert tx0["transactionIndex"] == "0x0"
      assert tx1["transactionIndex"] == "0x1"
    end
  end

  describe "format_transaction/2" do
    test "formats legacy transaction with all fields" do
      signed_tx = make_legacy_signed_tx()

      result =
        Formatters.format_transaction(signed_tx, %{
          block_hash: <<0::256>>,
          block_number: 42,
          tx_index: 0
        })

      assert result["type"] == "0x0"
      assert result["nonce"] == "0x5"
      assert result["gas"] == "0x5208"
      assert result["value"] == "0xf4240"
      assert result["input"] == "0x"
      assert result["v"] == "0x1b"
      assert result["r"] == "0x64"
      assert result["s"] == "0xc8"
      assert result["gasPrice"] == "0x77359400"
      assert result["blockNumber"] == "0x2a"
      assert result["transactionIndex"] == "0x0"
      assert String.starts_with?(result["hash"], "0x")
      assert String.starts_with?(result["to"], "0x")
    end

    test "formats EIP-1559 transaction with fee fields" do
      signed_tx = make_eip1559_signed_tx()

      result =
        Formatters.format_transaction(signed_tx, %{
          block_hash: <<0::256>>,
          block_number: 100,
          tx_index: 3
        })

      assert result["type"] == "0x2"
      assert result["nonce"] == "0xa"
      assert result["maxFeePerGas"] == "0x77359400"
      assert result["maxPriorityFeePerGas"] == "0x3b9aca00"
      assert result["input"] == "0xdead"
      assert result["accessList"] == []
      refute Map.has_key?(result, "gasPrice")
    end

    test "formats EIP-2930 transaction with access list" do
      signed_tx = make_eip2930_signed_tx()

      result =
        Formatters.format_transaction(signed_tx, %{
          block_hash: <<0::256>>,
          block_number: 50,
          tx_index: 1
        })

      assert result["type"] == "0x1"
      assert result["gasPrice"] == "0x59682f00"
      assert length(result["accessList"]) == 1

      [entry] = result["accessList"]
      assert String.starts_with?(entry["address"], "0x")
      assert length(entry["storageKeys"]) == 1
    end

    test "handles nil block context for pending transactions" do
      signed_tx = make_legacy_signed_tx()

      result =
        Formatters.format_transaction(signed_tx, %{
          block_hash: nil,
          block_number: nil,
          tx_index: nil
        })

      assert result["blockHash"] == nil
      assert result["blockNumber"] == nil
      assert result["transactionIndex"] == nil
    end
  end

  describe "compute_block_hash/1" do
    test "returns a 32-byte hash" do
      header = sample_header()
      hash = Formatters.compute_block_hash(header)

      assert byte_size(hash) == 32
    end

    test "matches EthStorage.Encoding.block_hash" do
      header = sample_header()
      expected = EthStorage.Encoding.block_hash(header)
      actual = Formatters.compute_block_hash(header)

      assert actual == expected
    end

    test "different headers produce different hashes" do
      header1 = sample_header()
      header2 = %{sample_header() | number: 99}

      hash1 = Formatters.compute_block_hash(header1)
      hash2 = Formatters.compute_block_hash(header2)

      assert hash1 != hash2
    end
  end

  describe "format_balance/1" do
    test "formats zero balance" do
      assert Formatters.format_balance(0) == "0x0"
    end

    test "formats positive balance" do
      assert Formatters.format_balance(1_000_000) == "0xf4240"
    end

    test "formats 1 ether in wei" do
      one_ether = 1_000_000_000_000_000_000
      result = Formatters.format_balance(one_ether)
      assert result == "0xde0b6b3a7640000"
    end
  end

  describe "format_receipt/1" do
    test "formats a simple receipt" do
      receipt = %EthCore.Types.Receipt{
        type: 2,
        status: 1,
        cumulative_gas_used: 21_000,
        logs_bloom: <<0::2048>>,
        logs: []
      }

      result = Formatters.format_receipt(receipt)

      assert result["type"] == "0x2"
      assert result["status"] == "0x1"
      assert result["cumulativeGasUsed"] == "0x5208"
      assert result["logs"] == []
    end

    test "formats receipt with logs" do
      log = %EthCore.Types.Log{
        address: <<1::160>>,
        topics: [<<2::256>>, <<3::256>>],
        data: <<4, 5, 6>>
      }

      receipt = %EthCore.Types.Receipt{
        type: 0,
        status: 1,
        cumulative_gas_used: 42_000,
        logs_bloom: <<0::2048>>,
        logs: [log]
      }

      result = Formatters.format_receipt(receipt)

      assert length(result["logs"]) == 1
      [formatted_log] = result["logs"]

      assert String.starts_with?(formatted_log["address"], "0x")
      assert length(formatted_log["topics"]) == 2
      assert formatted_log["data"] == "0x040506"
    end
  end

  describe "format_full_receipt/2" do
    test "includes block context fields" do
      receipt = %EthCore.Types.Receipt{
        type: 2,
        status: 1,
        cumulative_gas_used: 21_000,
        logs_bloom: <<0::2048>>,
        logs: []
      }

      result =
        Formatters.format_full_receipt(receipt, %{
          tx_hash: <<1::256>>,
          tx_index: 0,
          block_hash: <<2::256>>,
          block_number: 100,
          from: <<3::160>>,
          to: <<4::160>>,
          gas_used: 21_000,
          contract_address: nil
        })

      assert result["transactionHash"] != nil
      assert result["transactionIndex"] == "0x0"
      assert result["blockNumber"] == "0x64"
      assert result["status"] == "0x1"
      assert result["gasUsed"] == "0x5208"
      assert result["contractAddress"] == nil
      assert String.starts_with?(result["from"], "0x")
      assert String.starts_with?(result["to"], "0x")
    end
  end
end
