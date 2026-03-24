defmodule EthDashboard.Router do
  @moduledoc """
  Plug router serving the dashboard HTML page and SSE event stream.

  Routes:
  - `GET /`       — serves the self-contained HTML dashboard page
  - `GET /events` — SSE stream pushing JSON metrics every second
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/" do
    html = EthDashboard.Html.page()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  get "/events" do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    stream_events(conn)
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  @spec stream_events(Plug.Conn.t()) :: Plug.Conn.t()
  defp stream_events(conn) do
    state = EthDashboard.Collector.get_state()
    data = Jason.encode!(serialize(state))

    case Plug.Conn.chunk(conn, "data: #{data}\n\n") do
      {:ok, conn} ->
        Process.sleep(1000)
        stream_events(conn)

      {:error, _} ->
        conn
    end
  end

  @spec serialize(%EthDashboard.Collector{}) :: map()
  defp serialize(state) do
    %{
      sync: %{
        status: state.sync_status,
        current_block: state.current_block,
        target_block: state.target_block,
        blocks_per_sec: state.blocks_per_sec
      },
      peers: %{
        count: state.peer_count,
        list: state.peers
      },
      engine: state.engine_requests,
      blocks: state.latest_blocks,
      network: %{
        sent: state.messages_sent,
        received: state.messages_received
      },
      system: %{
        memory_mb: state.memory_mb,
        processes: state.process_count,
        uptime: state.uptime_seconds
      }
    }
  end
end
