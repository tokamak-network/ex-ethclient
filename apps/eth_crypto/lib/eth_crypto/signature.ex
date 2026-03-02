defmodule EthCrypto.Signature do
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @half_n div(@secp256k1_n, 2)

  @spec sign(<<_::256>>, <<_::256>>) :: {:ok, {<<_::256>>, <<_::256>>, 0 | 1}}
  def sign(<<msg_hash::binary-size(32)>>, <<privkey::binary-size(32)>>) do
    {:ok, {r, s, recovery_id}} = ExSecp256k1.sign(msg_hash, privkey)

    {s_normalized, flipped} = normalize_s(s)

    recovery_id =
      if flipped do
        # Flip recovery id when s is flipped
        1 - recovery_id
      else
        recovery_id
      end

    {:ok, {r, s_normalized, recovery_id}}
  end

  @spec recover(<<_::256>>, <<_::512>>, 0 | 1) :: {:ok, binary()} | {:error, term()}
  def recover(<<msg_hash::binary-size(32)>>, <<r::binary-size(32), s::binary-size(32)>>, recovery_id)
      when recovery_id in [0, 1] do
    ExSecp256k1.recover(msg_hash, r, s, recovery_id)
  end

  @spec normalize_s(<<_::256>>) :: {<<_::256>>, boolean()}
  def normalize_s(<<s_bin::binary-size(32)>>) do
    s_int = :binary.decode_unsigned(s_bin)

    if s_int > @half_n do
      normalized = @secp256k1_n - s_int
      {<<normalized::unsigned-big-size(256)>>, true}
    else
      {s_bin, false}
    end
  end
end
