defmodule EthRpc.JwtAuth do
  @moduledoc "JWT authentication plug for Engine API endpoints."

  @behaviour Plug

  @doc "Initialize the plug with options."
  @spec init(keyword()) :: keyword()
  @impl true
  def init(opts), do: opts

  @doc """
  Validate JWT token if configured.

  If no jwt_secret is configured (dev mode), all requests pass through.
  If a secret is configured, the Authorization header must contain a
  valid Bearer token.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  @impl true
  def call(conn, _opts) do
    case jwt_secret() do
      nil ->
        conn

      secret ->
        validate_token(conn, secret)
    end
  end

  @spec validate_token(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defp validate_token(conn, secret) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        if valid_jwt?(token, secret) do
          conn
        else
          reject(conn)
        end

      _ ->
        reject(conn)
    end
  end

  @spec valid_jwt?(String.t(), binary()) :: boolean()
  defp valid_jwt?(token, secret) do
    case String.split(token, ".") do
      [header_b64, payload_b64, signature_b64] ->
        verify_signature(header_b64, payload_b64, signature_b64, secret)

      _ ->
        false
    end
  end

  @spec verify_signature(String.t(), String.t(), String.t(), binary()) ::
          boolean()
  defp verify_signature(header_b64, payload_b64, sig_b64, secret) do
    message = header_b64 <> "." <> payload_b64
    expected = :crypto.mac(:hmac, :sha256, secret, message)

    case Base.url_decode64(sig_b64, padding: false) do
      {:ok, signature} ->
        byte_size(signature) == byte_size(expected) and
          :crypto.hash_equals(expected, signature)

      :error ->
        false
    end
  end

  @spec reject(Plug.Conn.t()) :: Plug.Conn.t()
  defp reject(conn) do
    body = Jason.encode!(%{"error" => "Unauthorized"})

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(401, body)
    |> Plug.Conn.halt()
  end

  @spec jwt_secret() :: binary() | nil
  defp jwt_secret do
    case Application.get_env(:eth_rpc, :jwt_secret) do
      nil ->
        nil

      {:file, path} ->
        read_secret_file(path)

      secret when is_binary(secret) ->
        secret
    end
  end

  @spec read_secret_file(String.t()) :: binary() | nil
  defp read_secret_file(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.trim()
        |> Base.decode16(case: :mixed)
        |> case do
          {:ok, binary} -> binary
          :error -> String.trim(content)
        end

      {:error, _} ->
        nil
    end
  end
end
