defmodule EthCrypto.Signature do
  @moduledoc """
  secp256k1 ECDSA signature operations using ex_secp256k1 NIF.

  All signatures are EIP-2 normalized: s-values are guaranteed to be
  in the lower half of the curve order (s <= secp256k1n/2).
  """

  @type compact_sig :: <<_::512>>

  # secp256k1 curve order
  @secp256k1n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1n_half div(@secp256k1n, 2)

  @doc """
  Signs a 32-byte message hash with a 32-byte private key.
  Returns `{:ok, {r, s, recovery_id}}` where r and s are 32-byte binaries
  and recovery_id is 0 or 1.

  The s-value is EIP-2 normalized (s <= secp256k1n/2).
  """
  @spec sign(<<_::256>>, <<_::256>>) ::
          {:ok, {<<_::256>>, <<_::256>>, 0 | 1}} | {:error, term()}
  def sign(<<_::binary-size(32)>> = hash, <<_::binary-size(32)>> = private_key) do
    case ExSecp256k1.sign(hash, private_key) do
      {:ok, {r, s, recovery_id}} ->
        {s_normalized, recovery_id_normalized} = normalize_s(s, recovery_id)
        {:ok, {r, s_normalized, recovery_id_normalized}}

      {:error, reason} ->
        {:error, {:signing_failed, reason}}
    end
  end

  @doc """
  Recovers the uncompressed public key (64 bytes, without 0x04 prefix)
  from a message hash and signature components.
  """
  @spec recover(<<_::256>>, <<_::256>>, <<_::256>>, 0 | 1) ::
          {:ok, <<_::512>>} | {:error, term()}
  def recover(hash, r, s, recovery_id)
      when is_binary(hash) and byte_size(hash) == 32 and
             is_binary(r) and byte_size(r) == 32 and
             is_binary(s) and byte_size(s) == 32 and
             recovery_id in [0, 1] do
    case ExSecp256k1.recover(hash, r, s, recovery_id) do
      {:ok, <<4, public_key::binary-size(64)>>} ->
        {:ok, public_key}

      {:ok, <<_::binary-size(64)>> = public_key} ->
        {:ok, public_key}

      {:ok, unexpected} ->
        {:error, {:unexpected_public_key_format, byte_size(unexpected)}}

      {:error, reason} ->
        {:error, {:recovery_failed, reason}}
    end
  end

  @doc """
  Checks if a signature's s-value is in the lower half of the curve order (EIP-2).
  Returns true if the s-value is valid for Ethereum transaction inclusion.
  """
  @spec low_s?(<<_::256>>) :: boolean()
  def low_s?(<<_::binary-size(32)>> = s) do
    :binary.decode_unsigned(s) <= @secp256k1n_half
  end

  @doc "Generates a new random private key."
  @spec generate_private_key() :: <<_::256>>
  def generate_private_key do
    :crypto.strong_rand_bytes(32)
  end

  @doc "Derives the uncompressed public key (64 bytes) from a private key."
  @spec public_key_from_private(<<_::256>>) :: {:ok, <<_::512>>} | {:error, term()}
  def public_key_from_private(<<_::binary-size(32)>> = private_key) do
    case ExSecp256k1.create_public_key(private_key) do
      {:ok, <<4, public_key::binary-size(64)>>} ->
        {:ok, public_key}

      {:ok, <<_::binary-size(64)>> = public_key} ->
        {:ok, public_key}

      {:ok, unexpected} ->
        {:error, {:unexpected_public_key_format, byte_size(unexpected)}}

      error ->
        {:error, {:key_derivation_failed, error}}
    end
  end

  # EIP-2: If s > secp256k1n/2, replace s with secp256k1n - s and flip recovery_id.
  defp normalize_s(s_bin, recovery_id) do
    s_int = :binary.decode_unsigned(s_bin)

    if s_int > @secp256k1n_half do
      new_s = @secp256k1n - s_int
      new_recovery_id = if recovery_id == 0, do: 1, else: 0
      {pad_to_32(:binary.encode_unsigned(new_s)), new_recovery_id}
    else
      {s_bin, recovery_id}
    end
  end

  defp pad_to_32(bin) when byte_size(bin) == 32, do: bin

  defp pad_to_32(bin) when byte_size(bin) < 32 do
    padding_size = (32 - byte_size(bin)) * 8
    <<0::size(padding_size), bin::binary>>
  end

  defp pad_to_32(bin) when byte_size(bin) > 32 do
    # Truncation should never happen with valid secp256k1 values.
    # If it does, this indicates a bug upstream.
    binary_part(bin, byte_size(bin) - 32, 32)
  end
end
