defmodule EthRpc.JwtAuthTest do
  use ExUnit.Case, async: true

  alias EthRpc.JwtAuth

  describe "call/2" do
    test "passes through when no secret configured" do
      Application.delete_env(:eth_rpc, :jwt_secret)
      conn = build_conn()

      result = JwtAuth.call(conn, [])
      refute result.halted
    end

    test "rejects when secret configured but no token" do
      secret = :crypto.strong_rand_bytes(32)
      Application.put_env(:eth_rpc, :jwt_secret, secret)

      conn = build_conn()
      result = JwtAuth.call(conn, [])

      assert result.halted
      assert result.status == 401

      Application.delete_env(:eth_rpc, :jwt_secret)
    end

    test "rejects when secret configured with invalid token" do
      secret = :crypto.strong_rand_bytes(32)
      Application.put_env(:eth_rpc, :jwt_secret, secret)

      conn = build_conn_with_auth("Bearer invalid.token.here")
      result = JwtAuth.call(conn, [])

      assert result.halted
      assert result.status == 401

      Application.delete_env(:eth_rpc, :jwt_secret)
    end

    test "accepts valid JWT token" do
      secret = :crypto.strong_rand_bytes(32)
      Application.put_env(:eth_rpc, :jwt_secret, secret)

      token = build_jwt(secret)
      conn = build_conn_with_auth("Bearer #{token}")
      result = JwtAuth.call(conn, [])

      refute result.halted

      Application.delete_env(:eth_rpc, :jwt_secret)
    end
  end

  # --- Helpers ---

  @spec build_conn() :: Plug.Conn.t()
  defp build_conn do
    Plug.Test.conn(:post, "/", "")
  end

  @spec build_conn_with_auth(String.t()) :: Plug.Conn.t()
  defp build_conn_with_auth(auth) do
    Plug.Test.conn(:post, "/", "")
    |> Plug.Conn.put_req_header("authorization", auth)
  end

  @spec build_jwt(binary()) :: String.t()
  defp build_jwt(secret) do
    header = Base.url_encode64("{\"alg\":\"HS256\",\"typ\":\"JWT\"}", padding: false)

    payload =
      Base.url_encode64(
        Jason.encode!(%{"iat" => System.system_time(:second)}),
        padding: false
      )

    message = header <> "." <> payload
    signature = :crypto.mac(:hmac, :sha256, secret, message)
    sig_b64 = Base.url_encode64(signature, padding: false)

    message <> "." <> sig_b64
  end
end
