defmodule EthRpc.EngineIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the Engine API.

  Simulates a consensus layer client driving the execution layer through
  the full newPayload -> forkchoiceUpdated -> getPayload cycle.
  """

  use ExUnit.Case, async: false

  alias EthRpc.{Engine, ForkChoice, PayloadManager}
  alias EthRpc.Hex
  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{BlockStore, Store}

  @zero_hash <<0::256>>
  @test_store :engine_integration_store

  setup do
    # Stop any previously registered processes from other test modules
    for name <- [PayloadManager, ForkChoice, @test_store] do
      case GenServer.whereis(name) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 100)
      end
    end

    {:ok, _} = Store.start_link(name: @test_store)
    {:ok, _} = PayloadManager.start_link(name: PayloadManager)
    {:ok, _} = ForkChoice.start_link(name: ForkChoice)

    Application.put_env(:eth_rpc, :store, {Store, @test_store})

    on_exit(fn ->
      Application.delete_env(:eth_rpc, :store)
    end)

    :ok
  end

  describe "full CL integration cycle" do
    test "newPayloadV3 -> forkchoiceUpdatedV3 -> getPayloadV3" do
      # Step 1: Store genesis block (parent)
      genesis = build_genesis_block()
      {:ok, genesis_hash} = BlockStore.store_block(genesis, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      # Step 2: Build execution payload for block 1
      timestamp = System.system_time(:second)
      payload = build_execution_payload(1, genesis_hash, timestamp)

      # Step 3: Send engine_newPayloadV3
      versioned_hashes = []
      parent_beacon_root = Hex.encode_data(@zero_hash)

      assert {:ok, np_result} =
               Engine.new_payload_v3([
                 payload,
                 versioned_hashes,
                 parent_beacon_root
               ])

      assert np_result["status"] == "VALID",
             "Expected VALID but got #{np_result["status"]}: " <>
               "#{inspect(np_result["validationError"])}"

      block_hash = np_result["latestValidHash"]
      assert block_hash != nil
      assert is_binary(block_hash)

      # Step 4: Send engine_forkchoiceUpdatedV3 to set head
      fc_state = %{
        "headBlockHash" => block_hash,
        "safeBlockHash" => Hex.encode_data(genesis_hash),
        "finalizedBlockHash" => Hex.encode_data(genesis_hash)
      }

      assert {:ok, fcu_result} =
               Engine.forkchoice_updated_v3([fc_state])

      assert fcu_result["payloadStatus"]["status"] == "VALID"
      assert fcu_result["payloadId"] == nil

      # Step 5: Verify fork choice state was updated
      state = ForkChoice.get_state()
      {:ok, block_hash_bin} = Hex.decode_data(block_hash)
      assert state.head_hash == block_hash_bin

      # Step 6: Send forkchoiceUpdated with payloadAttributes to start building
      next_timestamp = timestamp + 12

      payload_attrs = %{
        "timestamp" => Hex.encode_quantity(next_timestamp),
        "prevRandao" => Hex.encode_data(@zero_hash),
        "suggestedFeeRecipient" => Hex.encode_data(<<0::160>>),
        "withdrawals" => [],
        "parentBeaconBlockRoot" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, fcu_result2} =
               Engine.forkchoice_updated_v3([fc_state, payload_attrs])

      assert fcu_result2["payloadStatus"]["status"] == "VALID"
      payload_id = fcu_result2["payloadId"]
      assert payload_id != nil

      # Step 7: Send engine_getPayloadV3
      assert {:ok, gp_result} = Engine.get_payload_v3([payload_id])

      assert Map.has_key?(gp_result, "executionPayload")
      assert Map.has_key?(gp_result, "blockValue")
      assert Map.has_key?(gp_result, "blobsBundle")
      assert gp_result["shouldOverrideBuilder"] == false
    end

    test "newPayloadV3 returns SYNCING for unknown parent" do
      payload = build_execution_payload(1, <<99::256>>, 1_000_000)

      assert {:ok, result} =
               Engine.new_payload_v3([
                 payload,
                 [],
                 Hex.encode_data(@zero_hash)
               ])

      assert result["status"] == "SYNCING"
      assert result["latestValidHash"] == nil
    end

    test "forkchoiceUpdatedV3 returns SYNCING for unknown head" do
      fc_state = %{
        "headBlockHash" => Hex.encode_data(<<42::256>>),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, result} = Engine.forkchoice_updated_v3([fc_state])
      assert result["payloadStatus"]["status"] == "SYNCING"
    end

    test "multiple blocks can be added sequentially" do
      genesis = build_genesis_block()
      {:ok, genesis_hash} = BlockStore.store_block(genesis, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      base_time = System.system_time(:second)

      # Add block 1
      payload_1 = build_execution_payload(1, genesis_hash, base_time)

      assert {:ok, r1} =
               Engine.new_payload_v3([
                 payload_1,
                 [],
                 Hex.encode_data(@zero_hash)
               ])

      assert r1["status"] == "VALID"
      hash_1 = r1["latestValidHash"]

      # Set head to block 1
      fc1 = %{
        "headBlockHash" => hash_1,
        "safeBlockHash" => Hex.encode_data(genesis_hash),
        "finalizedBlockHash" => Hex.encode_data(genesis_hash)
      }

      assert {:ok, fcu1} = Engine.forkchoice_updated_v3([fc1])
      assert fcu1["payloadStatus"]["status"] == "VALID"

      # Add block 2 (parent = block 1)
      {:ok, hash_1_bin} = Hex.decode_data(hash_1)
      payload_2 = build_execution_payload(2, hash_1_bin, base_time + 12)

      assert {:ok, r2} =
               Engine.new_payload_v3([
                 payload_2,
                 [],
                 Hex.encode_data(@zero_hash)
               ])

      assert r2["status"] == "VALID"
      hash_2 = r2["latestValidHash"]
      assert hash_2 != hash_1

      # Set head to block 2
      fc2 = %{
        "headBlockHash" => hash_2,
        "safeBlockHash" => hash_1,
        "finalizedBlockHash" => Hex.encode_data(genesis_hash)
      }

      assert {:ok, fcu2} = Engine.forkchoice_updated_v3([fc2])
      assert fcu2["payloadStatus"]["status"] == "VALID"
    end

    test "exchange_capabilities returns all supported methods" do
      assert {:ok, methods} = Engine.exchange_capabilities([["engine_newPayloadV3"]])
      assert is_list(methods)
      assert "engine_newPayloadV3" in methods
      assert "engine_forkchoiceUpdatedV3" in methods
      assert "engine_getPayloadV3" in methods
      assert "engine_getClientVersionV1" in methods
    end
  end

  # --- Test helpers ---

  @spec build_genesis_block() :: Block.t()
  defp build_genesis_block do
    %Block{
      header: %BlockHeader{
        parent_hash: @zero_hash,
        ommers_hash: @zero_hash,
        coinbase: <<0::160>>,
        state_root: @zero_hash,
        transactions_root: @zero_hash,
        receipts_root: @zero_hash,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 0,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: 0,
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

  @spec build_execution_payload(non_neg_integer(), binary(), non_neg_integer()) ::
          map()
  defp build_execution_payload(number, parent_hash, timestamp) do
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
      "timestamp" => Hex.encode_quantity(timestamp),
      "extraData" => "0x",
      "baseFeePerGas" => Hex.encode_quantity(875_000_000),
      "blockHash" => Hex.encode_data(@zero_hash),
      "transactions" => [],
      "withdrawals" => [],
      "blobGasUsed" => "0x0",
      "excessBlobGas" => "0x0"
    }
  end
end
