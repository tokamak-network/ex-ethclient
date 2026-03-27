defmodule EthRpc.MetricsTest do
  use ExUnit.Case, async: false

  alias EthRpc.Metrics

  setup do
    # Detach any lingering handlers from prior test runs
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

    # Delete the ETS table if it exists from a prior run
    if :ets.whereis(:eth_metrics) != :undefined do
      :ets.delete(:eth_metrics)
    end

    start_supervised!(Metrics)
    :ok
  end

  describe "counter operations" do
    test "increments a counter with no labels" do
      assert Metrics.get_counter(:test_counter) == 0

      Metrics.increment_counter(:test_counter)
      assert Metrics.get_counter(:test_counter) == 1

      Metrics.increment_counter(:test_counter)
      assert Metrics.get_counter(:test_counter) == 2
    end

    test "increments counters with different labels independently" do
      Metrics.increment_counter(:rpc_request_total, %{method: "eth_chainId"})
      Metrics.increment_counter(:rpc_request_total, %{method: "eth_chainId"})
      Metrics.increment_counter(:rpc_request_total, %{method: "eth_blockNumber"})

      assert Metrics.get_counter(:rpc_request_total, %{method: "eth_chainId"}) == 2
      assert Metrics.get_counter(:rpc_request_total, %{method: "eth_blockNumber"}) == 1
    end
  end

  describe "gauge operations" do
    test "sets and retrieves a gauge value" do
      assert Metrics.get_gauge(:chain_height) == 0

      Metrics.set_gauge(:chain_height, 12345)
      assert Metrics.get_gauge(:chain_height) == 12345
    end

    test "overwrites previous gauge value" do
      Metrics.set_gauge(:peer_count, 5)
      assert Metrics.get_gauge(:peer_count) == 5

      Metrics.set_gauge(:peer_count, 3)
      assert Metrics.get_gauge(:peer_count) == 3
    end
  end

  describe "histogram operations" do
    test "records observations and updates sum/count" do
      Metrics.observe_histogram(:rpc_request_duration_seconds, 0.05)
      Metrics.observe_histogram(:rpc_request_duration_seconds, 0.15)

      output = Metrics.format_prometheus()
      assert output =~ "eth_rpc_request_duration_seconds_count"
      assert output =~ "eth_rpc_request_duration_seconds_sum"
      assert output =~ "eth_rpc_request_duration_seconds_bucket"
    end
  end

  describe "telemetry event handling" do
    test "handles rpc request stop event" do
      :telemetry.execute(
        [:eth, :rpc, :request, :stop],
        %{duration: 5_000_000},
        %{method: "eth_getBalance"}
      )

      assert Metrics.get_counter(:rpc_request_total, %{method: "eth_getBalance"}) == 1
    end

    test "handles block processed event" do
      :telemetry.execute(
        [:eth, :block, :processed],
        %{duration: 50_000_000},
        %{block_number: 100, tx_count: 3}
      )

      assert Metrics.get_counter(:block_processed_total, %{}) == 1
      assert Metrics.get_counter(:tx_processed_total, %{}) == 3
    end

    test "handles peer connected event" do
      :telemetry.execute(
        [:eth, :peer, :connected],
        %{count: 1},
        %{node_id: "test-node"}
      )

      assert Metrics.get_counter(:peer_connected_total, %{}) == 1
    end

    test "handles peer disconnected event" do
      :telemetry.execute(
        [:eth, :peer, :disconnected],
        %{count: 0},
        %{node_id: "test-node"}
      )

      assert Metrics.get_counter(:peer_disconnected_total, %{}) == 1
    end
  end

  describe "format_prometheus/0" do
    test "outputs valid Prometheus text format for counters" do
      Metrics.increment_counter(:rpc_request_total, %{method: "eth_chainId"})

      output = Metrics.format_prometheus()
      assert output =~ "# HELP eth_rpc_request_total Counter metric."
      assert output =~ "# TYPE eth_rpc_request_total counter"
      assert output =~ ~s(eth_rpc_request_total{method="eth_chainId"} 1)
    end

    test "outputs valid Prometheus text format for gauges" do
      Metrics.set_gauge(:chain_height, 42)

      output = Metrics.format_prometheus()
      assert output =~ "# HELP eth_chain_height Gauge metric."
      assert output =~ "# TYPE eth_chain_height gauge"
      assert output =~ "eth_chain_height 42"
    end

    test "outputs valid Prometheus text format for histograms" do
      Metrics.observe_histogram(:rpc_request_duration_seconds, 0.05)

      output = Metrics.format_prometheus()
      assert output =~ "# TYPE eth_rpc_request_duration_seconds histogram"
      assert output =~ ~s(eth_rpc_request_duration_seconds_bucket{le="0.1"})
      assert output =~ ~s(eth_rpc_request_duration_seconds_bucket{le="+Inf"})
      assert output =~ "eth_rpc_request_duration_seconds_count"
      assert output =~ "eth_rpc_request_duration_seconds_sum"
    end

    test "returns placeholder when no metrics table exists" do
      # Stop the metrics server to simulate missing table
      stop_supervised!(Metrics)

      if :ets.whereis(:eth_metrics) != :undefined do
        :ets.delete(:eth_metrics)
      end

      output = Metrics.format_prometheus()
      assert output =~ "No metrics available"
    end
  end

  describe "metrics/0" do
    test "returns a list of telemetry metrics definitions" do
      metrics = Metrics.metrics()
      assert is_list(metrics)
      assert length(metrics) > 0
    end
  end

  describe "telemetry_events/0" do
    test "returns all handled event names" do
      events = Metrics.telemetry_events()
      assert [:eth, :rpc, :request, :stop] in events
      assert [:eth, :block, :processed] in events
      assert [:eth, :peer, :connected] in events
      assert [:eth, :peer, :disconnected] in events
    end
  end
end
