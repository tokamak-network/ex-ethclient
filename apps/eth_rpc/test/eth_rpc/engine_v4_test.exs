defmodule EthRpc.EngineV4Test do
  @moduledoc "Tests for engine_newPayloadV4 with 4 params (execution_requests)."
  use ExUnit.Case, async: false

  alias EthRpc.{Engine, ForkChoice, PayloadManager}
  alias EthRpc.Hex
  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{BlockStore, Store}

  @zero_hash <<0::256>>
  @test_store :engine_v4_test_store

  setup do
    ensure_started(@test_store, fn -> Store.start_link(name: @test_store) end)
    ensure_started(PayloadManager, fn -> PayloadManager.start_link(name: PayloadManager) end)
    ensure_started(ForkChoice, fn -> ForkChoice.start_link(name: ForkChoice) end)

    Application.put_env(:eth_rpc, :store, {Store, @test_store})

    on_exit(fn ->
      Application.delete_env(:eth_rpc, :store)
    end)

    :ok
  end

  defp ensure_started(name, start_fn) do
    case GenServer.whereis(name) do
      nil -> {:ok, _} = start_fn.()
      _pid -> :ok
    end
  end

  describe "new_payload_v4/1" do
    test "accepts 4 params (payload, hashes, beacon_root, execution_requests)" do
      parent = build_test_block(0)
      {:ok, parent_hash} = BlockStore.store_block(parent, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      payload = build_execution_payload(1, parent_hash)
      blob_hashes = []
      beacon_root = Hex.encode_data(@zero_hash)
      execution_requests = ["0x00", "0x01", "0x02"]

      assert {:ok, result} =
               Engine.new_payload_v4([
                 payload,
                 blob_hashes,
                 beacon_root,
                 execution_requests
               ])

      assert result["status"] == "VALID"
      assert result["latestValidHash"] != nil
    end

    test "accepts 4 params and stores block without parent" do
      payload = build_execution_payload(1, <<99::256>>)
      blob_hashes = []
      beacon_root = Hex.encode_data(@zero_hash)
      execution_requests = ["0x00", "0x01", "0x02"]

      assert {:ok, result} =
               Engine.new_payload_v4([
                 payload,
                 blob_hashes,
                 beacon_root,
                 execution_requests
               ])

      # CL-validated blocks are stored even without a local parent
      assert result["status"] == "VALID"
      assert result["latestValidHash"] != nil
    end

    test "stored block can be found by forkchoiceUpdatedV3" do
      parent = build_test_block(0)
      {:ok, parent_hash} = BlockStore.store_block(parent, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      payload = build_execution_payload(1, parent_hash)
      execution_requests = ["0x00", "0x01", "0x02"]

      assert {:ok, np_result} =
               Engine.new_payload_v4([
                 payload,
                 [],
                 Hex.encode_data(@zero_hash),
                 execution_requests
               ])

      assert np_result["status"] == "VALID"
      block_hash = np_result["latestValidHash"]

      # Now FCU should find the block
      fc_state = %{
        "headBlockHash" => block_hash,
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, fcu_result} = Engine.forkchoice_updated_v3([fc_state])
      assert fcu_result["payloadStatus"]["status"] == "VALID"
    end

    test "handles payload with transactions" do
      parent = build_test_block(0)
      {:ok, parent_hash} = BlockStore.store_block(parent, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      # Add some raw transaction hex strings
      payload =
        build_execution_payload(1, parent_hash)
        |> Map.put("transactions", [
          "0xf86c0185012a05f20082520894" <>
            "0000000000000000000000000000000000000001" <>
            "80801ba0" <>
            "0000000000000000000000000000000000000000000000000000000000000001" <>
            "a0" <>
            "0000000000000000000000000000000000000000000000000000000000000002"
        ])

      assert {:ok, result} =
               Engine.new_payload_v4([
                 payload,
                 [],
                 Hex.encode_data(@zero_hash),
                 []
               ])

      assert result["status"] == "VALID"
    end

    test "returns INVALID for malformed payload" do
      # Empty map - missing required fields
      assert {:ok, result} =
               Engine.new_payload_v4([
                 %{},
                 [],
                 Hex.encode_data(@zero_hash),
                 []
               ])

      assert result["status"] == "INVALID"
    end

    test "handles non-map first param gracefully" do
      assert {:ok, result} =
               Engine.new_payload_v4(["not_a_map"])

      assert result["status"] == "INVALID"
    end
  end

  # --- Test helpers ---

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  @spec build_test_block(non_neg_integer()) :: Block.t()
  defp build_test_block(number) do
    base_ts = 1_700_000_000 + number * 12

    %Block{
      header: %BlockHeader{
        parent_hash: @zero_hash,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: @zero_hash,
        transactions_root: @zero_hash,
        receipts_root: @zero_hash,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: number,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: base_ts,
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
  end

  @spec build_execution_payload(non_neg_integer(), binary()) :: map()
  defp build_execution_payload(number, parent_hash) do
    child_ts = 1_700_000_000 + number * 12

    %{
      "parentHash" => Hex.encode_data(parent_hash),
      "feeRecipient" => Hex.encode_data(<<0::160>>),
      "stateRoot" => Hex.encode_data(@zero_hash),
      "receiptsRoot" => Hex.encode_data(@zero_hash),
      "logsBloom" => Hex.encode_data(<<0::2048>>),
      "prevRandao" => Hex.encode_data(@zero_hash),
      "blockNumber" => Hex.encode_quantity(number),
      "gasLimit" => Hex.encode_quantity(30_000_000),
      "gasUsed" => Hex.encode_quantity(0),
      "timestamp" => Hex.encode_quantity(child_ts),
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
