defmodule EthCore.Signer do
  alias EthCrypto.{Key, Signature}
  alias EthCore.Transaction.{Legacy, EIP2930, EIP1559, EIP4844, EIP7702}

  @spec sign_transaction(struct(), <<_::256>>, keyword()) :: struct()
  def sign_transaction(tx, privkey, opts \\ [])

  def sign_transaction(%Legacy{} = tx, privkey, opts) do
    chain_id = Keyword.get(opts, :chain_id)

    msg_hash =
      if chain_id do
        Legacy.signing_hash(tx, chain_id)
      else
        Legacy.signing_hash(tx)
      end

    {:ok, {r, s, recovery_id}} = Signature.sign(msg_hash, privkey)

    v =
      if chain_id do
        chain_id * 2 + 35 + recovery_id
      else
        27 + recovery_id
      end

    %{tx | v: v, r: :binary.decode_unsigned(r), s: :binary.decode_unsigned(s)}
  end

  def sign_transaction(%EIP2930{} = tx, privkey, _opts) do
    sign_typed_tx(tx, privkey, &EIP2930.signing_hash/1)
  end

  def sign_transaction(%EIP1559{} = tx, privkey, _opts) do
    sign_typed_tx(tx, privkey, &EIP1559.signing_hash/1)
  end

  def sign_transaction(%EIP4844{} = tx, privkey, _opts) do
    sign_typed_tx(tx, privkey, &EIP4844.signing_hash/1)
  end

  def sign_transaction(%EIP7702{} = tx, privkey, _opts) do
    sign_typed_tx(tx, privkey, &EIP7702.signing_hash/1)
  end

  defp sign_typed_tx(tx, privkey, hash_fn) do
    msg_hash = hash_fn.(tx)
    {:ok, {r, s, recovery_id}} = Signature.sign(msg_hash, privkey)
    %{tx | v: recovery_id, r: :binary.decode_unsigned(r), s: :binary.decode_unsigned(s)}
  end

  @spec recover_sender(struct()) :: {:ok, <<_::160>>} | {:error, term()}
  def recover_sender(%Legacy{v: v} = tx) do
    case legacy_recovery_params(tx, v) do
      {:ok, msg_hash, recovery_id} -> do_recover(msg_hash, tx.r, tx.s, recovery_id)
      {:error, _} = err -> err
    end
  end

  def recover_sender(%EIP2930{v: v, r: r, s: s} = tx) do
    msg_hash = EIP2930.signing_hash(tx)
    do_recover(msg_hash, r, s, v)
  end

  def recover_sender(%EIP1559{v: v, r: r, s: s} = tx) do
    msg_hash = EIP1559.signing_hash(tx)
    do_recover(msg_hash, r, s, v)
  end

  def recover_sender(%EIP4844{v: v, r: r, s: s} = tx) do
    msg_hash = EIP4844.signing_hash(tx)
    do_recover(msg_hash, r, s, v)
  end

  def recover_sender(%EIP7702{v: v, r: r, s: s} = tx) do
    msg_hash = EIP7702.signing_hash(tx)
    do_recover(msg_hash, r, s, v)
  end

  defp legacy_recovery_params(tx, v) when v in [27, 28] do
    {:ok, Legacy.signing_hash(tx), v - 27}
  end

  defp legacy_recovery_params(tx, v) when v >= 35 do
    chain_id = div(v - 35, 2)
    recovery_id = v - (chain_id * 2 + 35)
    {:ok, Legacy.signing_hash(tx, chain_id), recovery_id}
  end

  defp legacy_recovery_params(_tx, v) do
    {:error, "invalid legacy v value: #{v}"}
  end

  defp do_recover(msg_hash, r_int, s_int, recovery_id) when recovery_id in [0, 1] do
    with {:ok, r} <- to_32_bytes(r_int),
         {:ok, s} <- to_32_bytes(s_int) do
      case Signature.recover(msg_hash, r <> s, recovery_id) do
        {:ok, pubkey} -> {:ok, Key.public_key_to_address(pubkey)}
        error -> error
      end
    end
  end

  defp do_recover(_msg_hash, _r, _s, recovery_id) do
    {:error, "invalid recovery_id: #{recovery_id}"}
  end

  defp to_32_bytes(0), do: {:ok, <<0::256>>}

  defp to_32_bytes(int) when is_integer(int) and int > 0 do
    bin = :binary.encode_unsigned(int)

    case byte_size(bin) do
      n when n <= 32 ->
        padding_size = 32 - n
        {:ok, <<0::size(padding_size * 8)>> <> bin}

      _ ->
        {:error, "value overflow: #{int} exceeds 32 bytes"}
    end
  end

  defp to_32_bytes(int), do: {:error, "invalid signature value: #{int}"}
end
