defmodule EthRpc.MetricsPollerTest do
  use ExUnit.Case, async: false

  alias EthRpc.{Metrics, MetricsPoller}

  setup do
    Enum.each(
      [
        "eth-rpc-request",
        "eth-block-processed",
        "eth-tx-processed",
        "eth-peer-connected",
        "eth-peer-disconnected"
      ],
      &:telemetry.detach/1
    )

    if :ets.whereis(:eth_metrics) != :undefined do
      :ets.delete(:eth_metrics)
    end

    start_supervised!(Metrics)
    :ok
  end

  describe "measure_chain_height/0" do
    test "sets the chain_height gauge to 0 when store is not running" do
      MetricsPoller.measure_chain_height()
      assert Metrics.get_gauge(:chain_height) == 0
    end
  end

  describe "measure_peer_count/0" do
    test "sets the peer_count gauge to 0 when peer manager is not running" do
      MetricsPoller.measure_peer_count()
      assert Metrics.get_gauge(:peer_count) == 0
    end
  end

  describe "measure_mempool_size/0" do
    test "sets the mempool_size gauge to 0 when mempool is not running" do
      MetricsPoller.measure_mempool_size()
      assert Metrics.get_gauge(:mempool_size) == 0
    end
  end

  describe "measure_sync_progress/0" do
    test "sets the sync_progress gauge to 100.0" do
      MetricsPoller.measure_sync_progress()
      assert Metrics.get_gauge(:sync_progress) == 100.0
    end
  end

  describe "child_spec/1" do
    test "returns a valid child spec" do
      spec = MetricsPoller.child_spec(period: 10_000)
      assert spec.id == MetricsPoller
      assert is_tuple(spec.start)
    end

    test "uses default period when not specified" do
      spec = MetricsPoller.child_spec()
      assert spec.id == MetricsPoller
    end
  end
end
