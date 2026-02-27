defmodule EthNet.RLPx.Handshake do
  @moduledoc """
  EIP-8 RLPx handshake: generates auth/ack messages and derives session keys.

  Auth message (initiator → responder):
    size(2) || ECIES(rlp([sig, pubkey, nonce, version]) || padding)

  Ack message (responder → initiator):
    size(2) || ECIES(rlp([ephemeral_pubkey, nonce, version]) || padding)

  Session key derivation:
    ephemeral_shared = ECDH(ephemeral_priv, remote_ephemeral_pub)
    shared_secret = keccak256(ephemeral_shared || keccak256(nonce_r || nonce_i))
    aes_secret = keccak256(ephemeral_shared || shared_secret)
    mac_secret = keccak256(ephemeral_shared || aes_secret)
  """

  alias EthCrypto.{ECIES, Hash, Signature}
  alias EthNet.RLPx.Mac

  @auth_vsn 4
  @ack_vsn 4
  @nonce_size 32

  defstruct [
    :private_key,
    :public_key,
    :ephemeral_private_key,
    :ephemeral_public_key,
    :nonce,
    :remote_public_key,
    :remote_ephemeral_public_key,
    :remote_nonce,
    :auth_msg,
    :ack_msg,
    :initiator?
  ]

  @type t :: %__MODULE__{}

  @doc "Creates an initiator handshake state."
  @spec initiator(<<_::256>>, <<_::512>>, <<_::512>>) :: t()
  def initiator(private_key, public_key, remote_public_key) do
    ephemeral_private = :crypto.strong_rand_bytes(32)
    {:ok, ephemeral_public} = Signature.public_key_from_private(ephemeral_private)
    nonce = :crypto.strong_rand_bytes(@nonce_size)

    %__MODULE__{
      private_key: private_key,
      public_key: public_key,
      ephemeral_private_key: ephemeral_private,
      ephemeral_public_key: ephemeral_public,
      nonce: nonce,
      remote_public_key: remote_public_key,
      initiator?: true
    }
  end

  @doc """
  Builds the EIP-8 auth message.
  Returns `{:ok, auth_bytes, updated_state}`.
  """
  @spec build_auth(t()) :: {:ok, binary(), t()}
  def build_auth(%__MODULE__{initiator?: true} = state) do
    # sig = sign(static_shared_secret XOR nonce, ephemeral_private_key)
    {:ok, shared_secret} = ECIES.ecdh(state.remote_public_key, state.private_key)
    signed_data = :crypto.exor(shared_secret, state.nonce)
    {:ok, {r, s, v}} = Signature.sign(signed_data, state.ephemeral_private_key)

    sig = r <> s <> <<v>>

    auth_body =
      ExRLP.encode([
        sig,
        state.public_key,
        state.nonce,
        @auth_vsn
      ])

    # Add random padding (100-300 bytes) for EIP-8
    padding = :crypto.strong_rand_bytes(100 + :rand.uniform(200))
    plaintext = auth_body <> padding

    # EIP-8: size prefix is used as shared MAC data (s2) in ECIES
    ecies_overhead = 65 + 16 + 32
    size = byte_size(plaintext) + ecies_overhead
    size_prefix = <<size::big-unsigned-16>>

    {:ok, encrypted} = ECIES.encrypt(plaintext, state.remote_public_key, size_prefix)
    auth_msg = size_prefix <> encrypted

    {:ok, auth_msg, %{state | auth_msg: auth_msg}}
  end

  @doc """
  Reads and processes an auth message (responder side).
  Returns `{:ok, responder_state}` with the remote public key extracted.
  """
  @spec read_auth(binary(), <<_::256>>, <<_::512>>) :: {:ok, t()} | {:error, term()}
  def read_auth(<<size::big-unsigned-16, rest::binary>>, private_key, public_key) do
    encrypted = binary_part(rest, 0, size)
    size_prefix = <<size::big-unsigned-16>>

    case ECIES.decrypt(encrypted, private_key, size_prefix) do
      {:ok, plaintext} ->
        # Strip EIP-8 padding: only decode the RLP prefix
        {rlp_data, _padding} = split_rlp(plaintext)
        [sig, remote_pubkey, remote_nonce, _version | _] = ExRLP.decode(rlp_data)

        # Recover ephemeral public key from signature
        {:ok, shared_secret} = ECIES.ecdh(remote_pubkey, private_key)
        signed_data = :crypto.exor(shared_secret, remote_nonce)

        <<r::binary-size(32), s::binary-size(32), v>> = sig

        case Signature.recover(signed_data, r, s, v) do
          {:ok, remote_ephemeral} ->
            ephemeral_private = :crypto.strong_rand_bytes(32)
            {:ok, ephemeral_public} = Signature.public_key_from_private(ephemeral_private)
            nonce = :crypto.strong_rand_bytes(@nonce_size)

            state = %__MODULE__{
              private_key: private_key,
              public_key: public_key,
              ephemeral_private_key: ephemeral_private,
              ephemeral_public_key: ephemeral_public,
              nonce: nonce,
              remote_public_key: remote_pubkey,
              remote_ephemeral_public_key: remote_ephemeral,
              remote_nonce: remote_nonce,
              auth_msg: <<size::big-unsigned-16>> <> encrypted,
              initiator?: false
            }

            {:ok, state}

          {:error, reason} ->
            {:error, {:auth_sig_recovery_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:auth_decrypt_failed, reason}}
    end
  end

  @doc """
  Builds the EIP-8 ack message (responder side).
  Returns `{:ok, ack_bytes, updated_state}`.
  """
  @spec build_ack(t()) :: {:ok, binary(), t()}
  def build_ack(%__MODULE__{initiator?: false} = state) do
    ack_body =
      ExRLP.encode([
        state.ephemeral_public_key,
        state.nonce,
        @ack_vsn
      ])

    padding = :crypto.strong_rand_bytes(100 + :rand.uniform(200))
    plaintext = ack_body <> padding

    # EIP-8: size prefix is used as shared MAC data (s2) in ECIES
    ecies_overhead = 65 + 16 + 32
    size = byte_size(plaintext) + ecies_overhead
    size_prefix = <<size::big-unsigned-16>>

    {:ok, encrypted} = ECIES.encrypt(plaintext, state.remote_public_key, size_prefix)
    ack_msg = size_prefix <> encrypted

    {:ok, ack_msg, %{state | ack_msg: ack_msg}}
  end

  @doc """
  Reads and processes an ack message (initiator side).
  Returns `{:ok, updated_state}` with remote ephemeral key and nonce.
  """
  @spec read_ack(binary(), t()) :: {:ok, t()} | {:error, term()}
  def read_ack(<<size::big-unsigned-16, rest::binary>>, %__MODULE__{initiator?: true} = state) do
    encrypted = binary_part(rest, 0, size)
    size_prefix = <<size::big-unsigned-16>>

    case ECIES.decrypt(encrypted, state.private_key, size_prefix) do
      {:ok, plaintext} ->
        {rlp_data, _padding} = split_rlp(plaintext)
        [remote_ephemeral, remote_nonce, _version | _] = ExRLP.decode(rlp_data)

        {:ok,
         %{
           state
           | remote_ephemeral_public_key: remote_ephemeral,
             remote_nonce: remote_nonce,
             ack_msg: <<size::big-unsigned-16>> <> encrypted
         }}

      {:error, reason} ->
        {:error, {:ack_decrypt_failed, reason}}
    end
  end

  @doc """
  Derives session secrets from the completed handshake.
  Returns `{aes_secret, mac_secret, egress_mac, ingress_mac}`.
  """
  @spec derive_secrets(t()) :: {:ok, map()}
  def derive_secrets(%__MODULE__{} = state) do
    {:ok, ephemeral_shared} =
      ECIES.ecdh(state.remote_ephemeral_public_key, state.ephemeral_private_key)

    {nonce_i, nonce_r} =
      if state.initiator?,
        do: {state.nonce, state.remote_nonce},
        else: {state.remote_nonce, state.nonce}

    nonce_hash = Hash.keccak256(nonce_r <> nonce_i)
    shared_secret = Hash.keccak256(ephemeral_shared <> nonce_hash)
    aes_secret = Hash.keccak256(ephemeral_shared <> shared_secret)
    mac_secret = Hash.keccak256(ephemeral_shared <> aes_secret)

    # Initialize MAC states
    {egress_mac, ingress_mac} = init_macs(mac_secret, nonce_i, nonce_r, state)

    {:ok,
     %{
       aes_secret: aes_secret,
       mac_secret: mac_secret,
       egress_mac: egress_mac,
       ingress_mac: ingress_mac
     }}
  end

  defp init_macs(mac_secret, nonce_i, nonce_r, state) do
    # egress-mac = keccak256.init ^ (mac-secret XOR nonce_r) for initiator
    # ingress-mac = keccak256.init ^ (mac-secret XOR nonce_i) for initiator
    egress_seed =
      if state.initiator?,
        do: :crypto.exor(mac_secret, nonce_r),
        else: :crypto.exor(mac_secret, nonce_i)

    ingress_seed =
      if state.initiator?,
        do: :crypto.exor(mac_secret, nonce_i),
        else: :crypto.exor(mac_secret, nonce_r)

    # Feed auth and ack messages into MACs
    egress_mac = Mac.new(mac_secret) |> Mac.update(egress_seed)
    ingress_mac = Mac.new(mac_secret) |> Mac.update(ingress_seed)

    {auth_msg, ack_msg} =
      if state.initiator?,
        do: {state.auth_msg, state.ack_msg},
        else: {state.auth_msg, state.ack_msg}

    egress_mac =
      if state.initiator?,
        do: Mac.update(egress_mac, auth_msg),
        else: Mac.update(egress_mac, ack_msg)

    ingress_mac =
      if state.initiator?,
        do: Mac.update(ingress_mac, ack_msg),
        else: Mac.update(ingress_mac, auth_msg)

    {egress_mac, ingress_mac}
  end

  # Splits an RLP-prefixed binary from trailing padding.
  # Returns {rlp_bytes, remaining}.
  defp split_rlp(<<prefix, _::binary>> = data) when prefix >= 0xF8 do
    len_bytes = prefix - 0xF7
    <<_prefix, len_bin::binary-size(len_bytes), _::binary>> = data
    content_len = :binary.decode_unsigned(len_bin)
    total = 1 + len_bytes + content_len
    <<rlp::binary-size(total), rest::binary>> = data
    {rlp, rest}
  end

  defp split_rlp(<<prefix, _::binary>> = data) when prefix >= 0xC0 do
    total = 1 + (prefix - 0xC0)
    <<rlp::binary-size(total), rest::binary>> = data
    {rlp, rest}
  end

  defp split_rlp(data), do: {data, <<>>}
end
