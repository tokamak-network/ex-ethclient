defmodule EthRpc.EngineTest do
  use ExUnit.Case, async: false

  alias EthRpc.{Engine, ForkChoice, PayloadManager}
  alias EthRpc.Hex
  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{BlockStore, Store}

  @zero_hash <<0::256>>
  @test_store :engine_test_store

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

  describe "forkchoice_updated_v3/1" do
    test "returns SYNCING when head block not in store" do
      fc_state = %{
        "headBlockHash" => Hex.encode_data(<<1::256>>),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, result} = Engine.forkchoice_updated_v3([fc_state])
      assert result["payloadStatus"]["status"] == "SYNCING"
      assert result["payloadId"] == nil
    end

    test "returns VALID when head block exists in store" do
      block = build_test_block(0)
      {:ok, block_hash} = BlockStore.store_block(block, @test_store)

      fc_state = %{
        "headBlockHash" => Hex.encode_data(block_hash),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, result} = Engine.forkchoice_updated_v3([fc_state])
      assert result["payloadStatus"]["status"] == "VALID"
      assert result["payloadId"] == nil
    end

    test "returns payloadId when payloadAttributes provided" do
      block = build_test_block(0)
      {:ok, block_hash} = BlockStore.store_block(block, @test_store)

      fc_state = %{
        "headBlockHash" => Hex.encode_data(block_hash),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      payload_attrs = %{
        "timestamp" => "0x1",
        "prevRandao" => Hex.encode_data(@zero_hash),
        "suggestedFeeRecipient" => Hex.encode_data(<<0::160>>)
      }

      assert {:ok, result} =
               Engine.forkchoice_updated_v3([fc_state, payload_attrs])

      assert result["payloadStatus"]["status"] == "VALID"
      assert result["payloadId"] != nil
    end

    test "updates fork choice state" do
      block = build_test_block(0)
      {:ok, block_hash} = BlockStore.store_block(block, @test_store)

      fc_state = %{
        "headBlockHash" => Hex.encode_data(block_hash),
        "safeBlockHash" => Hex.encode_data(block_hash),
        "finalizedBlockHash" => Hex.encode_data(block_hash)
      }

      Engine.forkchoice_updated_v3([fc_state])

      state = ForkChoice.get_state()
      assert state.head_hash == block_hash
      assert state.safe_hash == block_hash
      assert state.finalized_hash == block_hash
    end
  end

  describe "new_payload_v3/1" do
    test "stores block and returns VALID even when parent not found" do
      payload = build_execution_payload(1, <<99::256>>)

      assert {:ok, result} =
               Engine.new_payload_v3([payload, [], Hex.encode_data(@zero_hash)])

      # CL-validated blocks are stored even without a local parent
      assert result["status"] == "VALID"
      assert result["latestValidHash"] != nil
    end

    test "returns VALID when block is stored successfully" do
      # Store parent block first
      parent = build_test_block(0)
      {:ok, parent_hash} = BlockStore.store_block(parent, @test_store)
      Store.set_latest_block_number(@test_store, 0)

      payload = build_execution_payload(1, parent_hash)

      assert {:ok, result} =
               Engine.new_payload_v3([payload, [], Hex.encode_data(@zero_hash)])

      assert result["status"] == "VALID"
      assert result["latestValidHash"] != nil
    end
  end

  describe "get_payload_v3/1" do
    test "returns payload for valid ID" do
      attrs = %{"timestamp" => "0x1"}
      {:ok, id} = PayloadManager.new_payload(attrs)

      assert {:ok, result} = Engine.get_payload_v3([Hex.encode_quantity(id)])
      assert result["executionPayload"] == attrs
      assert result["blockValue"] == "0x0"
      assert result["shouldOverrideBuilder"] == false
    end

    test "returns error for unknown payload ID" do
      assert {:error, -38001, "Unknown payload"} =
               Engine.get_payload_v3(["0x999"])
    end
  end

  describe "exchange_capabilities/1" do
    test "returns supported methods" do
      assert {:ok, methods} = Engine.exchange_capabilities([])
      assert "engine_forkchoiceUpdatedV3" in methods
      assert "engine_newPayloadV3" in methods
      assert "engine_getPayloadV3" in methods
    end
  end

  describe "dispatch via EthRpc.Eth" do
    test "engine_exchangeCapabilities dispatches correctly" do
      assert {:ok, methods} =
               EthRpc.Eth.handle("engine_exchangeCapabilities", [])

      assert is_list(methods)
    end

    test "engine methods are dispatched correctly" do
      fc_state = %{
        "headBlockHash" => Hex.encode_data(@zero_hash),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_forkchoiceUpdatedV3",
                 [fc_state]
               )

      assert {:ok, _} =
               EthRpc.Eth.handle("engine_newPayloadV3", [%{}])

      assert {:error, -38001, _} =
               EthRpc.Eth.handle("engine_getPayloadV3", ["0x999"])
    end
  end

  # --- Test helpers ---

  @spec build_test_block(non_neg_integer()) :: Block.t()
  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  defp build_test_block(number) do
    # Use a fixed base timestamp so child blocks can reliably be later
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
    # Timestamp must be strictly greater than parent (1_700_000_000)
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
