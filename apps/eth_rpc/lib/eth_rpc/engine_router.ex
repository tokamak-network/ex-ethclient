defmodule EthRpc.EngineRouter do
  @moduledoc """
  Plug router for the authenticated Engine API endpoint.

  Runs on a separate port (default 8551) and requires JWT authentication
  for all requests. Only engine_ methods are accepted; standard eth_/net_
  methods should use the main RPC router on port 8545.
  """

  use Plug.Router

  alias EthRpc.{Handler, JwtAuth}

  require Logger

  plug(JwtAuth)
  plug(:match)
  plug(:dispatch)

  post "/" do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, decoded} <- Jason.decode(body) do
      method = if is_map(decoded), do: decoded["method"], else: "batch"
      Logger.info("Engine API request: #{method}")
      handle_decoded(conn, decoded)
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

  @spec handle_decoded(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defp handle_decoded(conn, params) when is_list(params) do
    responses = Enum.map(params, &Handler.handle_request/1)
    send_json(conn, 200, responses)
  end

  defp handle_decoded(conn, params) when is_map(params) do
    response = Handler.handle_request(params)
    send_json(conn, 200, response)
  end

  defp handle_decoded(conn, _) do
    send_json(conn, 400, Handler.parse_error())
  end

  @spec send_json(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
