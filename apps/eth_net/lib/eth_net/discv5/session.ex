defmodule EthNet.DiscV5.Session do
  @moduledoc """
  DiscV5 session management for per-peer encryption state.

  Each session tracks:
  - Initiator and recipient keys derived via HKDF-SHA256
  - The nonce counter for outgoing messages
  - Challenge data for WHOAREYOU handshakes

  Session keys are derived from an ECDH shared secret using HKDF
  with the challenge data (id-nonce) as info.
  """

  alias EthCrypto.Hash

  @type t :: %__MODULE__{
          node_id: <<_::256>>,
          initiator_key: <<_::128>>,
          recipient_key: <<_::128>>,
          nonce_counter: non_neg_integer(),
          established_at: integer()
        }

  @enforce_keys [:node_id, :initiator_key, :recipient_key]
  defstruct [:node_id, :initiator_key, :recipient_key, nonce_counter: 0, established_at: 0]

  @type challenge :: %{
          id_nonce: <<_::128>>,
          enr_seq: non_neg_integer()
        }

  @doc "Creates a new challenge for a WHOAREYOU packet."
  @spec new_challenge(non_neg_integer()) :: challenge()
  def new_challenge(enr_seq \\ 0) do
    %{
      id_nonce: :crypto.strong_rand_bytes(16),
      enr_seq: enr_seq
    }
  end

  @doc """
  Derives session keys from ECDH shared secret and challenge data.

  Uses HKDF-SHA256 with:
  - IKM: ECDH shared secret
  - Salt: id-nonce
  - Info: "discovery v5 key agreement" ++ initiator_node_id ++ recipient_node_id

  Returns `{initiator_key, recipient_key}` each 16 bytes (AES-128-GCM keys).
  """
  @spec derive_keys(binary(), <<_::128>>, <<_::256>>, <<_::256>>) ::
          {:ok, {<<_::128>>, <<_::128>>}} | {:error, atom()}
  def derive_keys(shared_secret, id_nonce, initiator_id, recipient_id) do
    info = "discovery v5 key agreement" <> initiator_id <> recipient_id

    # HKDF-Extract
    prk = :crypto.mac(:hmac, :sha256, id_nonce, shared_secret)

    # HKDF-Expand: need 32 bytes (2 x 16-byte keys)
    t1 = :crypto.mac(:hmac, :sha256, prk, info <> <<1>>)
    initiator_key = binary_part(t1, 0, 16)

    t2 = :crypto.mac(:hmac, :sha256, prk, t1 <> info <> <<2>>)
    recipient_key = binary_part(t2, 0, 16)

    {:ok, {initiator_key, recipient_key}}
  end

  @doc "Creates a session from derived keys."
  @spec from_keys(<<_::256>>, <<_::128>>, <<_::128>>) :: t()
  def from_keys(node_id, initiator_key, recipient_key) do
    %__MODULE__{
      node_id: node_id,
      initiator_key: initiator_key,
      recipient_key: recipient_key,
      nonce_counter: 0,
      established_at: System.system_time(:second)
    }
  end

  @doc "Returns the next nonce and increments the counter."
  @spec next_nonce(t()) :: {<<_::96>>, t()}
  def next_nonce(%__MODULE__{nonce_counter: counter} = session) do
    # 12-byte nonce: 4 bytes zero padding + 8 bytes counter
    nonce = <<0::32, counter::unsigned-big-64>>
    {nonce, %{session | nonce_counter: counter + 1}}
  end

  @doc "Encrypts a message using AES-128-GCM with the initiator key and auto-generated nonce."
  @spec encrypt(t(), binary(), binary()) :: {:ok, binary(), t()} | {:error, atom()}
  def encrypt(%__MODULE__{initiator_key: key} = session, plaintext, ad) do
    {nonce, session} = next_nonce(session)

    case aes_gcm_encrypt(key, nonce, plaintext, ad) do
      {:ok, ciphertext} -> {:ok, ciphertext, session}
      error -> error
    end
  end

  @doc "Encrypts a message using AES-128-GCM with the initiator key and a provided nonce."
  @spec encrypt_with_nonce(t(), binary(), binary(), <<_::96>>) ::
          {:ok, binary()} | {:error, atom()}
  def encrypt_with_nonce(%__MODULE__{initiator_key: key}, plaintext, ad, nonce) do
    aes_gcm_encrypt(key, nonce, plaintext, ad)
  end

  @doc "Decrypts a message using AES-128-GCM with the recipient key."
  @spec decrypt(t(), binary(), <<_::96>>, binary()) :: {:ok, binary()} | {:error, atom()}
  def decrypt(%__MODULE__{recipient_key: key}, ciphertext, nonce, ad) do
    aes_gcm_decrypt(key, nonce, ciphertext, ad)
  end

  @doc "Computes the ID nonce signature for handshake authentication."
  @spec sign_id_nonce(<<_::128>>, <<_::256>>, <<_::256>>) :: binary()
  def sign_id_nonce(id_nonce, ephemeral_pubkey, dest_node_id) do
    challenge_data = "discovery v5 identity proof" <> id_nonce <> ephemeral_pubkey <> dest_node_id
    Hash.keccak256(challenge_data)
  end

  # --- Private helpers ---

  defp aes_gcm_encrypt(key, nonce, plaintext, ad) do
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, plaintext, ad, true)
    {:ok, ciphertext <> tag}
  rescue
    _ -> {:error, :encryption_failed}
  end

  defp aes_gcm_decrypt(key, nonce, ciphertext_and_tag, ad) do
    tag_size = 16

    if byte_size(ciphertext_and_tag) < tag_size do
      {:error, :ciphertext_too_short}
    else
      ct_len = byte_size(ciphertext_and_tag) - tag_size
      <<ciphertext::binary-size(ct_len), tag::binary-size(16)>> = ciphertext_and_tag

      case :crypto.crypto_one_time_aead(:aes_128_gcm, key, nonce, ciphertext, ad, tag, false) do
        :error -> {:error, :decryption_failed}
        plaintext -> {:ok, plaintext}
      end
    end
  rescue
    _ -> {:error, :decryption_failed}
  end
end
