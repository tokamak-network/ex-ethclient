defmodule EthRpc.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias EthRpc.Router

  @opts Router.init([])

  defp json_rpc_call(method, params \\ [], id \\ 1) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params,
        "id" => id
      })

    :post
    |> conn("/", body)
    |> put_req_header("content-type", "application/json")
    |> Router.call(@opts)
  end

  defp decode_response(conn) do
    Jason.decode!(conn.resp_body)
  end

  describe "single request" do
    test "returns valid JSON-RPC 2.0 response" do
      conn = json_rpc_call("eth_chainId")
      response = decode_response(conn)

      assert conn.status == 200
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"] == "0x1"
    end

    test "preserves request id" do
      conn = json_rpc_call("eth_chainId", [], 42)
      response = decode_response(conn)

      assert response["id"] == 42
    end

    test "returns content-type application/json" do
      conn = json_rpc_call("eth_chainId")

      content_type =
        conn.resp_headers
        |> Enum.find(fn {k, _v} -> k == "content-type" end)
        |> elem(1)

      assert content_type =~ "application/json"
    end
  end

  describe "batch request" do
    test "returns array of responses" do
      body =
        Jason.encode!([
          %{"jsonrpc" => "2.0", "method" => "eth_chainId", "id" => 1},
          %{"jsonrpc" => "2.0", "method" => "eth_blockNumber", "id" => 2}
        ])

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      responses = decode_response(conn)

      assert conn.status == 200
      assert is_list(responses)
      assert length(responses) == 2

      [r1, r2] = responses
      assert r1["id"] == 1
      assert r1["result"] == "0x1"
      assert r2["id"] == 2
      assert r2["result"] == "0x0"
    end
  end

  describe "error handling" do
    test "parse error for invalid JSON" do
      conn =
        :post
        |> conn("/", "not json at all{{{")
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      response = decode_response(conn)

      assert response["error"]["code"] == -32700
      assert response["id"] == nil
    end

    test "unknown method returns -32601" do
      conn = json_rpc_call("eth_nonExistent")
      response = decode_response(conn)

      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "not found"
    end

    test "missing method field returns error" do
      body = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1})

      conn =
        :post
        |> conn("/", body)
        |> put_req_header("content-type", "application/json")
        |> Router.call(@opts)

      response = decode_response(conn)

      assert response["error"]["code"] == -32600
    end
  end

  describe "non-POST requests" do
    test "GET returns 404" do
      conn =
        :get
        |> conn("/")
        |> Router.call(@opts)

      assert conn.status == 404
    end
  end
end
