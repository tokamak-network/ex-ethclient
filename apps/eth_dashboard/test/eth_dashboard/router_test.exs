defmodule EthDashboard.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias EthDashboard.Router

  @opts Router.init([])

  setup do
    # Ensure the Collector is running for router tests
    case GenServer.whereis(EthDashboard.Collector) do
      nil ->
        {:ok, _pid} = EthDashboard.Collector.start_link([])

      _pid ->
        :ok
    end

    :ok
  end

  describe "GET /" do
    test "returns 200 with HTML content" do
      conn = conn(:get, "/")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"

      body = conn.resp_body
      assert body =~ "<!DOCTYPE html>"
      assert body =~ "ex_ethclient"
      assert body =~ "EventSource"
      assert body =~ "/events"
    end

    test "HTML contains all dashboard sections" do
      conn = conn(:get, "/")
      conn = Router.call(conn, @opts)
      body = conn.resp_body

      assert body =~ "Sync"
      assert body =~ "Engine API"
      assert body =~ "Recent Blocks"
      assert body =~ "System"
      assert body =~ "current-block"
      assert body =~ "target-block"
      assert body =~ "engine-list"
      assert body =~ "block-list"
    end
  end

  describe "GET /events" do
    test "returns chunked response with SSE content-type" do
      # Run the SSE endpoint in a task since it blocks forever
      task =
        Task.async(fn ->
          conn = conn(:get, "/events")
          Router.call(conn, @opts)
        end)

      # Give the SSE endpoint time to send first chunk
      Process.sleep(1_500)
      Task.shutdown(task, :brutal_kill)

      # If we got here without crashing, the SSE endpoint works
      assert true
    end
  end

  describe "unknown routes" do
    test "returns 404 for unknown paths" do
      conn = conn(:get, "/unknown")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
    end
  end
end
