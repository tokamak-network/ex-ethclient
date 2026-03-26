defmodule EthRpc.EngineVersionsTest do
  use ExUnit.Case, async: false

  alias EthRpc.{Engine, ForkChoice, PayloadManager}
  alias EthRpc.Hex
  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{BlockStore, Store}

  @zero_hash <<0::256>>
  @test_store :engine_versions_test_store

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

  describe "forkchoiceUpdatedV1" do
    test "works without withdrawals in payload attributes" do
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
        "suggestedFeeRecipient" => Hex.encode_data(<<0::160>>),
        "withdrawals" => [%{"index" => "0x0"}],
        "parentBeaconBlockRoot" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, result} =
               Engine.forkchoice_updated_v1([fc_state, payload_attrs])

      assert result["payloadStatus"]["status"] == "VALID"
      assert result["payloadId"] != nil
    end

    test "returns SYNCING when head block not found" do
      fc_state = %{
        "headBlockHash" => Hex.encode_data(<<1::256>>),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, result} = Engine.forkchoice_updated_v1([fc_state])
      assert result["payloadStatus"]["status"] == "SYNCING"
    end
  end

  describe "forkchoiceUpdatedV2" do
    test "works with withdrawals in payload attributes" do
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
        "suggestedFeeRecipient" => Hex.encode_data(<<0::160>>),
        "withdrawals" => []
      }

      assert {:ok, result} =
               Engine.forkchoice_updated_v2([fc_state, payload_attrs])

      assert result["payloadStatus"]["status"] == "VALID"
      assert result["payloadId"] != nil
    end
  end

  describe "newPayloadV1" do
    test "accepts minimal payload and stores block without parent" do
      payload = build_execution_payload(1, <<99::256>>)

      assert {:ok, result} = Engine.new_payload_v1([payload])
      # CL-validated blocks are stored even without a local parent
      assert result["status"] == "VALID"
    end
  end

  describe "newPayloadV2" do
    test "accepts payload with blob hashes and stores block without parent" do
      payload = build_execution_payload(1, <<99::256>>)
      blob_hashes = [Hex.encode_data(<<1::256>>)]

      assert {:ok, result} =
               Engine.new_payload_v2([payload, blob_hashes])

      # CL-validated blocks are stored even without a local parent
      assert result["status"] == "VALID"
    end
  end

  describe "getPayloadV1" do
    test "returns just executionPayload" do
      attrs = %{"timestamp" => "0x1"}
      {:ok, id} = PayloadManager.new_payload(attrs)

      assert {:ok, result} =
               Engine.get_payload_v1([Hex.encode_quantity(id)])

      assert result["executionPayload"] == attrs
      refute Map.has_key?(result, "blockValue")
      refute Map.has_key?(result, "blobsBundle")
    end
  end

  describe "getPayloadV2" do
    test "returns executionPayload and blockValue" do
      attrs = %{"timestamp" => "0x1"}
      {:ok, id} = PayloadManager.new_payload(attrs)

      assert {:ok, result} =
               Engine.get_payload_v2([Hex.encode_quantity(id)])

      assert result["executionPayload"] == attrs
      assert result["blockValue"] == "0x0"
      refute Map.has_key?(result, "blobsBundle")
    end
  end

  describe "getPayloadBodiesByHashV1" do
    test "returns null for unknown hashes" do
      hashes = [Hex.encode_data(<<1::256>>), Hex.encode_data(<<2::256>>)]

      assert {:ok, bodies} =
               Engine.get_payload_bodies_by_hash_v1([hashes])

      assert length(bodies) == 2
      assert Enum.all?(bodies, &is_nil/1)
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = Engine.get_payload_bodies_by_hash_v1([])
    end
  end

  describe "getPayloadBodiesByRangeV1" do
    test "returns bodies for a range" do
      assert {:ok, bodies} =
               Engine.get_payload_bodies_by_range_v1(["0x0", "0x2"])

      assert is_list(bodies)
      assert length(bodies) == 2
    end

    test "returns empty list for invalid params" do
      assert {:ok, []} = Engine.get_payload_bodies_by_range_v1([])
    end
  end

  describe "getBlobsV1" do
    test "returns null for unknown versioned hashes" do
      hashes = [Hex.encode_data(<<1::256>>), Hex.encode_data(<<2::256>>)]

      assert {:ok, results} = Engine.get_blobs_v1([hashes])
      assert length(results) == 2
      assert Enum.all?(results, &is_nil/1)
    end

    test "returns empty list for no hashes" do
      assert {:ok, []} = Engine.get_blobs_v1([])
    end

    test "returns stored blob data and proof" do
      versioned_hash = <<1::256>>
      blob_data = :crypto.strong_rand_bytes(131_072)
      kzg_proof = :crypto.strong_rand_bytes(48)

      :ok =
        Store.put_blob(
          @test_store,
          versioned_hash,
          {blob_data, kzg_proof}
        )

      hashes = [Hex.encode_data(versioned_hash)]

      assert {:ok, [result]} = Engine.get_blobs_v1([hashes])
      assert result != nil
      assert result["blob"] == Hex.encode_data(blob_data)
      assert result["proof"] == Hex.encode_data(kzg_proof)
    end

    test "returns mixed results for known and unknown hashes" do
      known_hash = <<10::256>>
      unknown_hash = <<11::256>>
      blob_data = :crypto.strong_rand_bytes(131_072)
      kzg_proof = :crypto.strong_rand_bytes(48)

      :ok =
        Store.put_blob(
          @test_store,
          known_hash,
          {blob_data, kzg_proof}
        )

      hashes = [
        Hex.encode_data(known_hash),
        Hex.encode_data(unknown_hash)
      ]

      assert {:ok, [found, not_found]} = Engine.get_blobs_v1([hashes])

      assert found != nil
      assert found["blob"] == Hex.encode_data(blob_data)
      assert found["proof"] == Hex.encode_data(kzg_proof)
      assert not_found == nil
    end

    test "stores blobs via newPayloadV3 with blobsBundle" do
      versioned_hash = <<42::256>>
      blob_data = :crypto.strong_rand_bytes(131_072)
      kzg_proof = :crypto.strong_rand_bytes(48)

      payload =
        build_execution_payload(100, <<99::256>>)
        |> Map.put("blobVersionedHashes", [
          Hex.encode_data(versioned_hash)
        ])
        |> Map.put("blobsBundle", %{
          "blobs" => [Hex.encode_data(blob_data)],
          "proofs" => [Hex.encode_data(kzg_proof)],
          "commitments" => [Hex.encode_data(:crypto.strong_rand_bytes(48))]
        })

      assert {:ok, _result} = Engine.new_payload_v3([payload])

      # Verify blobs are now retrievable via getBlobsV1
      hashes = [Hex.encode_data(versioned_hash)]
      assert {:ok, [blob_result]} = Engine.get_blobs_v1([hashes])
      assert blob_result != nil
      assert blob_result["blob"] == Hex.encode_data(blob_data)
      assert blob_result["proof"] == Hex.encode_data(kzg_proof)
    end
  end

  describe "getClientVersionV1" do
    test "returns correct format" do
      assert {:ok, [client]} = Engine.get_client_version_v1([])
      assert client["code"] == "EE"
      assert client["name"] == "ExEthclient"
      assert client["version"] == "0.1.0"
      assert is_binary(client["commit"])
      assert String.starts_with?(client["commit"], "0x")
    end
  end

  describe "exchangeTransitionConfigurationV1" do
    test "echoes back provided config" do
      config = %{
        "terminalTotalDifficulty" => "0xC350",
        "terminalBlockHash" => Hex.encode_data(<<42::256>>),
        "terminalBlockNumber" => "0xA"
      }

      assert {:ok, result} =
               Engine.exchange_transition_config_v1([config])

      assert result["terminalTotalDifficulty"] == "0xC350"
      assert result["terminalBlockHash"] == Hex.encode_data(<<42::256>>)
      assert result["terminalBlockNumber"] == "0xA"
    end

    test "returns defaults when no config provided" do
      assert {:ok, result} =
               Engine.exchange_transition_config_v1([])

      assert result["terminalTotalDifficulty"] == "0x0"
      assert result["terminalBlockNumber"] == "0x0"
    end
  end

  describe "exchangeCapabilities" do
    test "lists all supported methods" do
      assert {:ok, methods} = Engine.exchange_capabilities([])

      assert "engine_forkchoiceUpdatedV1" in methods
      assert "engine_forkchoiceUpdatedV2" in methods
      assert "engine_forkchoiceUpdatedV3" in methods
      assert "engine_forkchoiceUpdatedV4" in methods
      assert "engine_newPayloadV1" in methods
      assert "engine_newPayloadV2" in methods
      assert "engine_newPayloadV3" in methods
      assert "engine_newPayloadV4" in methods
      assert "engine_getPayloadV1" in methods
      assert "engine_getPayloadV2" in methods
      assert "engine_getPayloadV3" in methods
      assert "engine_getPayloadV4" in methods
      assert "engine_getPayloadBodiesByHashV1" in methods
      assert "engine_getPayloadBodiesByRangeV1" in methods
      assert "engine_getBlobsV1" in methods
      assert "engine_getClientVersionV1" in methods
      assert "engine_exchangeTransitionConfigurationV1" in methods
    end
  end

  describe "dispatch via EthRpc.Eth" do
    test "V1 engine methods dispatch correctly" do
      fc_state = %{
        "headBlockHash" => Hex.encode_data(@zero_hash),
        "safeBlockHash" => Hex.encode_data(@zero_hash),
        "finalizedBlockHash" => Hex.encode_data(@zero_hash)
      }

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_forkchoiceUpdatedV1",
                 [fc_state]
               )

      assert {:ok, _} =
               EthRpc.Eth.handle("engine_newPayloadV1", [%{}])
    end

    test "new engine methods dispatch correctly" do
      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_getClientVersionV1",
                 []
               )

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_exchangeTransitionConfigurationV1",
                 []
               )

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_getBlobsV1",
                 []
               )

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_getPayloadBodiesByHashV1",
                 []
               )

      assert {:ok, _} =
               EthRpc.Eth.handle(
                 "engine_getPayloadBodiesByRangeV1",
                 []
               )
    end
  end

  # --- Test helpers ---

  @spec build_test_block(non_neg_integer()) :: Block.t()
  defp build_test_block(number) do
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
        number: number,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: System.system_time(:second),
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
      "timestamp" => Hex.encode_quantity(System.system_time(:second)),
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
