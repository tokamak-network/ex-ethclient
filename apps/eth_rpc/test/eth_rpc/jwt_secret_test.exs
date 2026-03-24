defmodule EthRpc.JwtSecretTest do
  use ExUnit.Case, async: true

  alias EthRpc.JwtSecret

  @test_dir Path.join(System.tmp_dir!(), "jwt_secret_test_#{:rand.uniform(100_000)}")

  setup do
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    :ok
  end

  describe "ensure_secret/1" do
    test "creates jwt.hex file if it does not exist" do
      path = JwtSecret.ensure_secret(@test_dir)

      assert File.exists?(path)
      assert String.ends_with?(path, "jwt.hex")

      content = File.read!(path) |> String.trim()
      assert byte_size(content) == 64
      assert Regex.match?(~r/^[0-9a-f]{64}$/, content)
    end

    test "does not overwrite existing jwt.hex file" do
      path = JwtSecret.ensure_secret(@test_dir)
      original = File.read!(path)

      path2 = JwtSecret.ensure_secret(@test_dir)
      assert path == path2
      assert File.read!(path) == original
    end

    test "creates parent directory if needed" do
      nested = Path.join(@test_dir, "nested/deep")
      path = JwtSecret.ensure_secret(nested)
      assert File.exists?(path)
    end
  end

  describe "read_secret/1" do
    test "reads a valid hex secret file" do
      path = JwtSecret.ensure_secret(@test_dir)

      assert {:ok, secret} = JwtSecret.read_secret(path)
      assert byte_size(secret) == 32
    end

    test "returns error for non-existent file" do
      assert {:error, :enoent} =
               JwtSecret.read_secret(Path.join(@test_dir, "nope.hex"))
    end

    test "returns error for invalid hex" do
      path = Path.join(@test_dir, "bad.hex")
      File.write!(path, "not-valid-hex")

      assert {:error, :invalid_hex} = JwtSecret.read_secret(path)
    end

    test "returns error for wrong length" do
      path = Path.join(@test_dir, "short.hex")
      File.write!(path, "aabbccdd")

      assert {:error, :invalid_secret_length} = JwtSecret.read_secret(path)
    end
  end

  describe "generate_token/1" do
    test "generates a valid JWT token" do
      secret = :crypto.strong_rand_bytes(32)
      token = JwtSecret.generate_token(secret)

      parts = String.split(token, ".")
      assert length(parts) == 3

      [header_b64, payload_b64, _sig] = parts

      {:ok, header_json} = Base.url_decode64(header_b64, padding: false)
      header = Jason.decode!(header_json)
      assert header["alg"] == "HS256"
      assert header["typ"] == "JWT"

      {:ok, payload_json} = Base.url_decode64(payload_b64, padding: false)
      payload = Jason.decode!(payload_json)
      assert is_integer(payload["iat"])
      # iat should be within last 5 seconds
      assert abs(payload["iat"] - System.system_time(:second)) < 5
    end

    test "token is verifiable with the same secret" do
      secret = :crypto.strong_rand_bytes(32)
      token = JwtSecret.generate_token(secret)

      [header_b64, payload_b64, sig_b64] = String.split(token, ".")
      message = header_b64 <> "." <> payload_b64
      expected = :crypto.mac(:hmac, :sha256, secret, message)
      {:ok, signature} = Base.url_decode64(sig_b64, padding: false)

      assert :crypto.hash_equals(expected, signature)
    end
  end

  describe "configure/1" do
    test "sets application env for jwt_secret" do
      path = JwtSecret.ensure_secret(@test_dir)
      :ok = JwtSecret.configure(path)

      assert Application.get_env(:eth_rpc, :jwt_secret) == {:file, path}
    end
  end
end
