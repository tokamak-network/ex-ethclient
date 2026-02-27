defmodule EthCrypto.ECIES do
  @moduledoc """
  ECIES (Elliptic Curve Integrated Encryption Scheme) for Ethereum.

  Used by the RLPx transport protocol for encrypting handshake messages.
  Implements the Ethereum variant with:
  - ECDH key agreement (secp256k1)
  - Concat KDF (NIST SP 800-56A) with SHA-256
  - AES-128-CTR encryption
  - HMAC-SHA-256 authentication

  Wire format: `0x04 || ephemeral_pubkey(64) || iv(16) || ciphertext || hmac(32)`
  """

  @prefix_byte <<0x04>>

  @doc """
  Encrypts plaintext for a recipient identified by their 64-byte uncompressed public key.

  The optional `shared_mac_data` (s2) is appended to the HMAC input for authentication.
  In EIP-8, this is the 2-byte auth/ack size prefix.
  """
  @spec encrypt(binary(), <<_::512>>, binary()) :: {:ok, binary()} | {:error, term()}
  def encrypt(plaintext, recipient_pubkey, shared_mac_data \\ <<>>)

  def encrypt(plaintext, <<_::binary-size(64)>> = recipient_pubkey, shared_mac_data)
      when is_binary(plaintext) do
    ephemeral_privkey = :crypto.strong_rand_bytes(32)

    with {:ok, <<4, ephemeral_pubkey::binary-size(64)>>} <-
           ExSecp256k1.create_public_key(ephemeral_privkey),
         {:ok, shared_secret} <- ecdh(recipient_pubkey, ephemeral_privkey) do
      <<enc_key::binary-size(16), mac_key_seed::binary-size(16)>> =
        concat_kdf(shared_secret, 32)

      mac_key = :crypto.hash(:sha256, mac_key_seed)
      iv = :crypto.strong_rand_bytes(16)
      ciphertext = :crypto.crypto_one_time(:aes_128_ctr, enc_key, iv, plaintext, true)
      tag = :crypto.mac(:hmac, :sha256, mac_key, iv <> ciphertext <> shared_mac_data)

      {:ok, @prefix_byte <> ephemeral_pubkey <> iv <> ciphertext <> tag}
    end
  end

  @doc """
  Decrypts ECIES ciphertext using the recipient's 32-byte private key.

  The optional `shared_mac_data` (s2) must match the value used during encryption.
  """
  @spec decrypt(binary(), <<_::256>>, binary()) :: {:ok, binary()} | {:error, term()}
  def decrypt(ciphertext, private_key, shared_mac_data \\ <<>>)

  def decrypt(
        <<4, ephemeral_pubkey::binary-size(64), iv::binary-size(16), rest::binary>>,
        <<_::binary-size(32)>> = private_key,
        shared_mac_data
      )
      when byte_size(rest) >= 32 do
    ciphertext_size = byte_size(rest) - 32
    <<ciphertext::binary-size(ciphertext_size), tag::binary-size(32)>> = rest

    with {:ok, shared_secret} <- ecdh(ephemeral_pubkey, private_key) do
      <<enc_key::binary-size(16), mac_key_seed::binary-size(16)>> =
        concat_kdf(shared_secret, 32)

      mac_key = :crypto.hash(:sha256, mac_key_seed)
      expected_tag = :crypto.mac(:hmac, :sha256, mac_key, iv <> ciphertext <> shared_mac_data)

      if secure_compare(tag, expected_tag) do
        plaintext = :crypto.crypto_one_time(:aes_128_ctr, enc_key, iv, ciphertext, false)
        {:ok, plaintext}
      else
        {:error, :invalid_mac}
      end
    end
  end

  def decrypt(_ciphertext, _private_key, _shared_mac_data),
    do: {:error, :invalid_ciphertext_format}

  @doc """
  Performs ECDH key agreement, returning the x-coordinate of the shared point.
  """
  @spec ecdh(<<_::512>>, <<_::256>>) :: {:ok, binary()} | {:error, term()}
  def ecdh(<<_::binary-size(64)>> = public_key, <<_::binary-size(32)>> = private_key) do
    full_pubkey = <<4>> <> public_key

    case ExSecp256k1.public_key_tweak_mult(full_pubkey, private_key) do
      {:ok, <<4, x::binary-size(32), _y::binary-size(32)>>} ->
        {:ok, x}

      {:error, reason} ->
        {:error, {:ecdh_failed, reason}}
    end
  end

  @doc false
  def concat_kdf(shared_secret, key_length) do
    hash_len = 32
    reps = div(key_length + hash_len - 1, hash_len)

    result =
      for counter <- 1..reps, into: <<>> do
        :crypto.hash(:sha256, <<counter::big-unsigned-32>> <> shared_secret)
      end

    binary_part(result, 0, key_length)
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_a, _b), do: false
end
