defmodule EthRpc.Router do
  @moduledoc """
  Plug router for the JSON-RPC 2.0 server.

  Accepts POST requests at "/" with JSON-RPC 2.0 payloads.
  Supports both single requests and batch requests (arrays).
  """

  use Plug.Router

  alias EthRpc.Handler

  plug(:match)
  plug(:dispatch)

  post "/" do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn),
         {:ok, decoded} <- Jason.decode(body) do
      case decoded do
        params when is_list(params) ->
          responses = Enum.map(params, &Handler.handle_request/1)
          send_json(conn, 200, responses)

        params when is_map(params) ->
          response = Handler.handle_request(params)
          send_json(conn, 200, response)

        _ ->
          send_json(conn, 400, Handler.parse_error())
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

  @spec send_json(Plug.Conn.t(), integer(), term()) :: Plug.Conn.t()
  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
