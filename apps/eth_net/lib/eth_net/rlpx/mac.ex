defmodule EthNet.RLPx.Mac do
  @moduledoc """
  Keccak-256 MAC state management for RLPx frame encryption.

  Since ExKeccak only provides one-shot hashing (no incremental API),
  we use a cumulative buffer approach: maintain all data fed into the MAC,
  and re-hash from scratch each time a digest is needed.

  This is O(n^2) overall but acceptable for MVP (typical session < 1MB).
  """

  defstruct [:secret, buffer: <<>>]

  @type t :: %__MODULE__{
          secret: <<_::256>>,
          buffer: binary()
        }

  @doc "Creates a new MAC state with the given mac_secret."
  @spec new(<<_::256>>) :: t()
  def new(<<_::binary-size(32)>> = secret) do
    %__MODULE__{secret: secret, buffer: <<>>}
  end

  @doc "Feeds data into the MAC state."
  @spec update(t(), binary()) :: t()
  def update(%__MODULE__{} = mac, data) when is_binary(data) do
    %{mac | buffer: mac.buffer <> data}
  end

  @doc """
  Computes the RLPx MAC for a frame header or body.

  The MAC computation is:
  1. `seed = AES-256-ECB(mac_secret, digest[:16]) XOR data[:16]`
  2. Feed `seed` into the running keccak state
  3. Return `digest[:16]` of the updated state

  Where `digest` is the current keccak256 hash of the buffer.
  """
  @spec compute(t(), binary()) :: {<<_::128>>, t()}
  def compute(%__MODULE__{} = mac, data) when is_binary(data) do
    # Current digest (first 16 bytes of keccak256)
    current_digest = digest_16(mac)

    # AES-256-ECB encrypt the digest with mac_secret
    encrypted = :crypto.crypto_one_time(:aes_256_ecb, mac.secret, current_digest, true)
    seed = :crypto.exor(binary_part(encrypted, 0, 16), pad_to_16(data))

    # Update MAC state with seed
    mac = update(mac, seed)

    # Return first 16 bytes of new digest
    {digest_16(mac), mac}
  end

  @doc "Returns the first 16 bytes of the current keccak256 digest."
  @spec digest_16(t()) :: <<_::128>>
  def digest_16(%__MODULE__{buffer: buffer}) do
    <<d::binary-size(16), _::binary>> = ExKeccak.hash_256(buffer)
    d
  end

  defp pad_to_16(data) when byte_size(data) >= 16, do: binary_part(data, 0, 16)
  defp pad_to_16(data), do: data <> :binary.copy(<<0>>, 16 - byte_size(data))
end
