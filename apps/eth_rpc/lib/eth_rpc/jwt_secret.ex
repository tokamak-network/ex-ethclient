defmodule EthRpc.JwtSecret do
  @moduledoc """
  Manages the shared JWT secret for Engine API authentication.

  Consensus layer clients (Lighthouse, Prysm, etc.) authenticate to
  the Engine API using a shared 32-byte secret stored as a hex file.
  This module handles generation, reading, and token creation.
  """

  @jwt_filename "jwt.hex"

  @doc """
  Ensures a JWT secret file exists in the given data directory.

  If no `jwt.hex` file exists, generates a new 32-byte random secret
  and writes it as lowercase hex. Returns the file path.
  """
  @spec ensure_secret(String.t()) :: String.t()
  def ensure_secret(datadir) do
    path = Path.join(datadir, @jwt_filename)
    File.mkdir_p!(datadir)

    unless File.exists?(path) do
      secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      File.write!(path, secret <> "\n")
    end

    path
  end

  @doc """
  Reads the JWT secret from a hex file and returns the raw 32-byte binary.
  """
  @spec read_secret(String.t()) :: {:ok, binary()} | {:error, term()}
  def read_secret(path) do
    case File.read(path) do
      {:ok, content} ->
        hex = content |> String.trim() |> String.replace_prefix("0x", "")

        case Base.decode16(hex, case: :mixed) do
          {:ok, <<_::256>> = secret} -> {:ok, secret}
          {:ok, _} -> {:error, :invalid_secret_length}
          :error -> {:error, :invalid_hex}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a JWT token signed with the given secret.

  The token follows the Engine API spec: HS256, with an `iat` claim
  set to the current UTC timestamp.
  """
  @spec generate_token(binary()) :: String.t()
  def generate_token(secret) when byte_size(secret) == 32 do
    header = Base.url_encode64(~s({"typ":"JWT","alg":"HS256"}), padding: false)
    iat = System.system_time(:second)
    payload = Base.url_encode64(~s({"iat":#{iat}}), padding: false)
    message = header <> "." <> payload
    signature = :crypto.mac(:hmac, :sha256, secret, message)
    sig_b64 = Base.url_encode64(signature, padding: false)
    message <> "." <> sig_b64
  end

  @doc """
  Configures the application to use the JWT secret at the given path.

  Sets the `:eth_rpc` `:jwt_secret` config to `{:file, path}` so that
  `EthRpc.JwtAuth` reads and validates tokens against this secret.
  """
  @spec configure(String.t()) :: :ok
  def configure(path) do
    Application.put_env(:eth_rpc, :jwt_secret, {:file, path})
    :ok
  end
end
