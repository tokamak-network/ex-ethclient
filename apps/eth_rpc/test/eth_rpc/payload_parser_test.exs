defmodule EthRpc.PayloadParserTest do
  use ExUnit.Case, async: true

  alias EthRpc.PayloadParser
  alias EthRpc.Hex
  alias EthCore.Types.{Block, BlockHeader}

  @zero_hash <<0::256>>

  describe "parse_execution_payload/1" do
    test "parses valid execution payload into Block struct" do
      payload = valid_payload()

      assert {:ok, %Block{} = block} =
               PayloadParser.parse_execution_payload(payload)

      assert %BlockHeader{} = block.header
      assert block.header.number == 1
      assert block.header.gas_limit == 30_000_000
      assert block.header.gas_used == 21_000
      assert block.header.base_fee_per_gas == 1_000_000_000
      assert block.header.difficulty == 0
      assert block.header.parent_hash == @zero_hash
      assert block.header.coinbase == <<0::160>>
      assert block.transactions == []
      assert block.ommers == []
    end

    test "parses withdrawals" do
      payload =
        valid_payload()
        |> Map.put("withdrawals", [
          %{
            "index" => "0x0",
            "validatorIndex" => "0x1",
            "address" => Hex.encode_data(<<1::160>>),
            "amount" => "0x100"
          }
        ])

      assert {:ok, %Block{} = block} =
               PayloadParser.parse_execution_payload(payload)

      assert [withdrawal] = block.withdrawals
      assert withdrawal.index == 0
      assert withdrawal.validator_index == 1
      assert withdrawal.amount == 256
    end

    test "returns error for non-map input" do
      assert {:error, :invalid_payload} =
               PayloadParser.parse_execution_payload("not a map")
    end

    test "returns error for missing required fields" do
      assert {:error, _} =
               PayloadParser.parse_execution_payload(%{})
    end
  end

  describe "to_execution_payload/2" do
    test "converts Block to execution payload map" do
      block = %Block{
        header: %BlockHeader{
          parent_hash: @zero_hash,
          ommers_hash: @zero_hash,
          coinbase: <<0::160>>,
          state_root: @zero_hash,
          transactions_root: @zero_hash,
          receipts_root: @zero_hash,
          logs_bloom: <<0::2048>>,
          difficulty: 0,
          number: 1,
          gas_limit: 30_000_000,
          gas_used: 21_000,
          timestamp: 1_000_000,
          extra_data: <<>>,
          mix_hash: @zero_hash,
          nonce: <<0::64>>,
          base_fee_per_gas: 1_000_000_000,
          blob_gas_used: 0,
          excess_blob_gas: 0
        },
        transactions: [],
        ommers: [],
        withdrawals: []
      }

      block_hash = <<42::256>>
      payload = PayloadParser.to_execution_payload(block, block_hash)

      assert payload["blockNumber"] == "0x1"
      assert payload["gasLimit"] == Hex.encode_quantity(30_000_000)
      assert payload["gasUsed"] == Hex.encode_quantity(21_000)
      assert payload["blockHash"] == Hex.encode_data(block_hash)
      assert payload["parentHash"] == Hex.encode_data(@zero_hash)
      assert payload["transactions"] == []
      assert payload["withdrawals"] == []
    end

    test "roundtrip parse -> to_execution_payload preserves data" do
      original = valid_payload()
      {:ok, block} = PayloadParser.parse_execution_payload(original)

      block_hash = <<42::256>>
      result = PayloadParser.to_execution_payload(block, block_hash)

      # Key fields should match after roundtrip
      assert result["blockNumber"] == original["blockNumber"]
      assert result["gasLimit"] == original["gasLimit"]
      assert result["gasUsed"] == original["gasUsed"]
      assert result["parentHash"] == original["parentHash"]
      assert result["feeRecipient"] == original["feeRecipient"]
    end
  end

  # --- Helper ---

  @spec valid_payload() :: map()
  defp valid_payload do
    %{
      "parentHash" => Hex.encode_data(@zero_hash),
      "feeRecipient" => Hex.encode_data(<<0::160>>),
      "stateRoot" => Hex.encode_data(@zero_hash),
      "receiptsRoot" => Hex.encode_data(@zero_hash),
      "logsBloom" => Hex.encode_data(<<0::2048>>),
      "prevRandao" => Hex.encode_data(@zero_hash),
      "blockNumber" => "0x1",
      "gasLimit" => Hex.encode_quantity(30_000_000),
      "gasUsed" => Hex.encode_quantity(21_000),
      "timestamp" => "0x1",
      "extraData" => "0x",
      "baseFeePerGas" => Hex.encode_quantity(1_000_000_000),
      "blockHash" => Hex.encode_data(@zero_hash),
      "transactions" => [],
      "withdrawals" => [],
      "blobGasUsed" => "0x0",
      "excessBlobGas" => "0x0"
    }
  end
end
