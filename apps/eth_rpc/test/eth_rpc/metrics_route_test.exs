defmodule EthRpc.MetricsRouteTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias EthRpc.{Metrics, Router}

  @opts Router.init([])

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

  describe "GET /metrics" do
    test "returns 200 with text/plain content type" do
      conn =
        :get
        |> conn("/metrics")
        |> Router.call(@opts)

      assert conn.status == 200

      content_type =
        conn.resp_headers
        |> Enum.find(fn {k, _v} -> k == "content-type" end)
        |> elem(1)

      assert content_type =~ "text/plain"
    end

    test "returns Prometheus formatted metrics" do
      Metrics.set_gauge(:chain_height, 999)
      Metrics.increment_counter(:block_processed_total)

      conn =
        :get
        |> conn("/metrics")
        |> Router.call(@opts)

      assert conn.resp_body =~ "eth_chain_height 999"
      assert conn.resp_body =~ "eth_block_processed_total"
    end

    test "emits telemetry for RPC requests visible in metrics" do
      body =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "method" => "eth_chainId",
          "params" => [],
          "id" => 1
        })

      :post
      |> conn("/", body)
      |> put_req_header("content-type", "application/json")
      |> Router.call(@opts)

      conn =
        :get
        |> conn("/metrics")
        |> Router.call(@opts)

      assert conn.resp_body =~ "eth_rpc_request_total"
      assert conn.resp_body =~ "eth_chainId"
    end
  end
end
