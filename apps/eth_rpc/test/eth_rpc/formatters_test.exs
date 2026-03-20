defmodule EthRpc.FormattersTest do
  use ExUnit.Case, async: true

  alias EthRpc.Formatters

  defp sample_header do
    %EthCore.Types.BlockHeader{
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
end
