defmodule EthRpc.Router do
  @moduledoc """
  Plug router for the JSON-RPC 2.0 server.

  Accepts POST requests at "/" with JSON-RPC 2.0 payloads.
  Supports both single requests and batch requests (arrays).
  Applies JWT authentication for engine_ methods when configured.
  """

  use Plug.Router

  alias EthRpc.Handler

  plug(:match)
  plug(:dispatch)

  get "/metrics" do
    body = EthRpc.Metrics.format_prometheus()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  get "/health" do
    health = EthChain.Health.check()

    payload = %{
      status: if(health.store == :up, do: "ok", else: "degraded"),
      block_number: health.chain_head || 0,
      peer_count: health.peer_count,
      syncing: health.syncing
    }

    send_json(conn, 200, payload)
  end

  post "/" do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, decoded} <- Jason.decode(body) do
      conn = maybe_auth_engine(conn, decoded)

      if conn.halted do
        conn
      else
        handle_decoded_with_telemetry(conn, decoded)
      end
    else
      {:error, %Jason.DecodeError{}} ->
        send_json(conn, 400, Handler.parse_error())

      {:error, _reason} ->
        send_json(conn, 400, Handler.parse_error())
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  @spec handle_decoded_with_telemetry(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp handle_decoded_with_telemetry(conn, params) when is_list(params) do
    responses = Enum.map(params, &handle_single_with_telemetry/1)
    send_json(conn, 200, responses)
  end

  defp handle_decoded_with_telemetry(conn, params) when is_map(params) do
    response = handle_single_with_telemetry(params)
    send_json(conn, 200, response)
  end

  defp handle_decoded_with_telemetry(conn, _) do
    send_json(conn, 400, Handler.parse_error())
  end

  @spec handle_single_with_telemetry(map()) :: map()
  defp handle_single_with_telemetry(%{"method" => method} = request) do
    start_time = System.monotonic_time()
    response = Handler.handle_request(request)
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:eth, :rpc, :request, :stop],
      %{duration: duration},
      %{method: method}
    )

    response
  end

  defp handle_single_with_telemetry(request) do
    Handler.handle_request(request)
  end

  @spec maybe_auth_engine(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp maybe_auth_engine(conn, decoded) do
    if engine_request?(decoded) do
      EthRpc.JwtAuth.call(conn, [])
    else
      conn
    end
  end

  @spec engine_request?(term()) :: boolean()
  defp engine_request?(%{"method" => "engine_" <> _}), do: true

  defp engine_request?(list) when is_list(list) do
    Enum.any?(list, &engine_request?/1)
  end

  defp engine_request?(_), do: false

  @spec send_json(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
