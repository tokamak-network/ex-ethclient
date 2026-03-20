defmodule EthRpc.EngineTest do
  use ExUnit.Case, async: true

  alias EthRpc.Engine

  describe "forkchoice_updated_v3/1" do
    test "returns SYNCING status" do
      assert {:ok, result} = Engine.forkchoice_updated_v3([%{}])

      assert result["payloadStatus"]["status"] == "SYNCING"
      assert result["payloadStatus"]["latestValidHash"] == nil
      assert result["payloadStatus"]["validationError"] == nil
      assert result["payloadId"] == nil
    end
  end

  describe "new_payload_v3/1" do
    test "returns SYNCING status" do
      assert {:ok, result} = Engine.new_payload_v3([%{}])

      assert result["status"] == "SYNCING"
      assert result["latestValidHash"] == nil
      assert result["validationError"] == nil
    end
  end

  describe "get_payload_v3/1" do
    test "returns unknown payload error" do
      assert {:error, -38001, "Unknown payload"} =
               Engine.get_payload_v3([%{}])
    end
  end

  describe "dispatch via EthRpc.Eth" do
    test "engine methods are dispatched correctly" do
      assert {:ok, _} =
               EthRpc.Eth.handle("engine_forkchoiceUpdatedV3", [%{}])

      assert {:ok, _} =
               EthRpc.Eth.handle("engine_newPayloadV3", [%{}])

      assert {:error, -38001, _} =
               EthRpc.Eth.handle("engine_getPayloadV3", [%{}])
    end
  end
end
