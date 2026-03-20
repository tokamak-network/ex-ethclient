defmodule EthRpc.Handler do
  @moduledoc """
  JSON-RPC 2.0 request handler.

  Validates request structure, dispatches to the appropriate namespace
  module, and formats JSON-RPC 2.0 responses.
  """

  alias EthRpc.Eth

  @doc """
  Processes a single JSON-RPC 2.0 request map and returns a response map.
  """
  @spec handle_request(map()) :: map()
  def handle_request(%{"method" => method} = request) do
    id = Map.get(request, "id")
    params = Map.get(request, "params", [])

    case Eth.handle(method, params) do
      {:ok, result} ->
        success_response(id, result)

      {:error, code, message} ->
        error_response(id, code, message)
    end
  end

  def handle_request(%{} = request) do
    id = Map.get(request, "id")
    error_response(id, -32600, "Invalid request: missing method")
  end

  @doc """
  Builds a JSON-RPC 2.0 success response.
  """
  @spec success_response(term(), term()) :: map()
  def success_response(id, result) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  @doc """
  Builds a JSON-RPC 2.0 error response.
  """
  @spec error_response(term(), integer(), String.t()) :: map()
  def error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    }
  end

  @doc """
  Builds a parse error response (no valid id available).
  """
  @spec parse_error() :: map()
  def parse_error do
    error_response(nil, -32700, "Parse error")
  end
end
