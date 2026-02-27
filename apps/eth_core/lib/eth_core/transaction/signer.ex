defmodule EthCore.Transaction.Signer do
  @moduledoc """
  Transaction signing and sender recovery for all Ethereum transaction types.

  Supports:
  - Pre-EIP-155 legacy transactions
  - EIP-155 replay-protected legacy transactions
  - EIP-2930 (Type 1)
  - EIP-1559 (Type 2)
  - EIP-4844 (Type 3)
  - EIP-7702 (Type 4)
  """

  require Logger

  alias EthCore.RLP
  alias EthCore.Types.{Address, SignedTransaction, Transaction}

  @doc """
  Signs a transaction with the given private key.
  Returns a SignedTransaction struct.
  """
  @spec sign(Transaction.t(), <<_::256>>, non_neg_integer() | nil) ::
          {:ok, SignedTransaction.t()} | {:error, term()}
  def sign(tx, private_key, chain_id \\ 1)

  def sign(%Transaction.Legacy{} = tx, private_key, chain_id) do
    payload = RLP.encode_for_signing(tx, chain_id)
    hash = EthCrypto.Hash.keccak256(payload)

    case EthCrypto.Signature.sign(hash, private_key) do
      {:ok, {r, s, recovery_id}} ->
        v =
          if chain_id do
            recovery_id + chain_id * 2 + 35
          else
            recovery_id + 27
          end

        {:ok,
         SignedTransaction.new(
           tx,
           v,
           :binary.decode_unsigned(r),
           :binary.decode_unsigned(s)
         )}

      {:error, _} = error ->
        Logger.warning("Legacy transaction signing failed: #{inspect(error)}")
        error
    end
  end

  def sign(%Transaction.EIP2930{} = tx, private_key, _chain_id) do
    sign_typed(tx, private_key)
  end

  def sign(%Transaction.EIP1559{} = tx, private_key, _chain_id) do
    sign_typed(tx, private_key)
  end

  def sign(%Transaction.EIP4844{} = tx, private_key, _chain_id) do
    sign_typed(tx, private_key)
  end

  def sign(%Transaction.EIP7702{} = tx, private_key, _chain_id) do
    sign_typed(tx, private_key)
  end

  @doc """
  Recovers the sender address from a signed transaction.
  """
  @spec recover_sender(SignedTransaction.t()) :: {:ok, Address.t()} | {:error, term()}
  def recover_sender(%SignedTransaction{tx: %Transaction.Legacy{} = tx, v: v, r: r, s: s}) do
    with {:ok, {recovery_id, signing_chain_id}} <- decode_legacy_v(v),
         :ok <- validate_signature_components(r, s) do
      payload = RLP.encode_for_signing(tx, signing_chain_id)
      hash = EthCrypto.Hash.keccak256(payload)
      do_recover(hash, r, s, recovery_id)
    end
  end

  def recover_sender(%SignedTransaction{tx: %Transaction.EIP2930{} = tx, v: v, r: r, s: s}) do
    recover_typed(tx, v, r, s)
  end

  def recover_sender(%SignedTransaction{tx: %Transaction.EIP1559{} = tx, v: v, r: r, s: s}) do
    recover_typed(tx, v, r, s)
  end

  def recover_sender(%SignedTransaction{tx: %Transaction.EIP4844{} = tx, v: v, r: r, s: s}) do
    recover_typed(tx, v, r, s)
  end

  def recover_sender(%SignedTransaction{tx: %Transaction.EIP7702{} = tx, v: v, r: r, s: s}) do
    recover_typed(tx, v, r, s)
  end

  # --- Private helpers ---

  defp sign_typed(tx, private_key) do
    payload = RLP.encode_for_signing(tx, nil)
    hash = EthCrypto.Hash.keccak256(payload)

    case EthCrypto.Signature.sign(hash, private_key) do
      {:ok, {r, s, recovery_id}} ->
        {:ok,
         SignedTransaction.new(
           tx,
           recovery_id,
           :binary.decode_unsigned(r),
           :binary.decode_unsigned(s)
         )}

      {:error, _} = error ->
        Logger.warning("Typed transaction signing failed: #{inspect(error)}")
        error
    end
  end

  defp recover_typed(tx, v, r, s) do
    with :ok <- validate_recovery_id(v),
         :ok <- validate_signature_components(r, s) do
      payload = RLP.encode_for_signing(tx, nil)
      hash = EthCrypto.Hash.keccak256(payload)
      do_recover(hash, r, s, v)
    end
  end

  defp validate_recovery_id(v) when v in [0, 1], do: :ok
  defp validate_recovery_id(v), do: {:error, {:invalid_recovery_id, v}}

  defp validate_signature_components(r, s)
       when is_integer(r) and r > 0 and is_integer(s) and s > 0,
       do: :ok

  defp validate_signature_components(r, s), do: {:error, {:invalid_signature, r: r, s: s}}

  defp do_recover(hash, r, s, recovery_id) do
    r_bin = integer_to_32_bytes(r)
    s_bin = integer_to_32_bytes(s)

    case EthCrypto.Signature.recover(hash, r_bin, s_bin, recovery_id) do
      {:ok, public_key} ->
        {:ok, Address.from_public_key(public_key)}

      {:error, _} = error ->
        error
    end
  end

  # Decodes legacy v value to {recovery_id, chain_id}
  # Pre-EIP-155: v = 27 or 28
  # EIP-155: v = chain_id * 2 + 35 + recovery_id
  defp decode_legacy_v(v) when v in [27, 28] do
    {:ok, {v - 27, nil}}
  end

  defp decode_legacy_v(v) when is_integer(v) and v >= 35 do
    recovery_id = rem(v - 35, 2)
    chain_id = div(v - 35, 2)
    {:ok, {recovery_id, chain_id}}
  end

  defp decode_legacy_v(v) do
    {:error, {:invalid_v_value, v}}
  end

  # Converts a non-negative integer to a zero-padded 32-byte binary.
  # Returns exactly 32 bytes for any valid secp256k1 scalar.
  defp integer_to_32_bytes(0), do: <<0::256>>

  defp integer_to_32_bytes(n) when is_integer(n) and n > 0 do
    bin = :binary.encode_unsigned(n)
    size = byte_size(bin)

    cond do
      size == 32 -> bin
      size < 32 -> <<0::size((32 - size) * 8), bin::binary>>
      size > 32 -> binary_part(bin, size - 32, 32)
    end
  end
end
