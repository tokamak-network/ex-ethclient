defmodule EthNet.RLPx.FrameCodec do
  @moduledoc """
  RLPx frame encoding/decoding with AES-128-CTR encryption, MAC authentication,
  and Snappy compression.

  Frame structure:
    header-ciphertext(16) || header-mac(16) || frame-ciphertext(padded) || frame-mac(16)

  Header (3 bytes + padding to 16):
    frame-size(3 bytes big-endian) || header-data || zero-padded to 16 bytes

  The AES-CTR counter is maintained across frames.
  """

  alias EthNet.RLPx.Mac

  defstruct [
    :aes_secret,
    :mac_secret,
    :enc_state,
    :dec_state,
    :egress_mac,
    :ingress_mac,
    snappy: false
  ]

  @type t :: %__MODULE__{}

  @doc "Initializes the frame codec with session secrets."
  @spec init(map()) :: t()
  def init(%{
        aes_secret: aes_secret,
        mac_secret: mac_secret,
        egress_mac: egress_mac,
        ingress_mac: ingress_mac
      }) do
    # AES-128-CTR with zero IV (counter starts at 0, maintained across frames)
    iv = <<0::128>>

    enc_state = :crypto.crypto_init(:aes_256_ctr, aes_secret, iv, true)
    dec_state = :crypto.crypto_init(:aes_256_ctr, aes_secret, iv, false)

    %__MODULE__{
      aes_secret: aes_secret,
      mac_secret: mac_secret,
      enc_state: enc_state,
      dec_state: dec_state,
      egress_mac: egress_mac,
      ingress_mac: ingress_mac,
      snappy: false
    }
  end

  @doc "Enables Snappy compression. Call after Hello exchange (protocol version >= 5)."
  @spec enable_snappy(t()) :: t()
  def enable_snappy(%__MODULE__{} = codec), do: %{codec | snappy: true}

  @doc """
  Encodes a frame: encrypts and authenticates a message.
  Returns `{:ok, frame_bytes, updated_codec}`.
  """
  @spec encode(t(), non_neg_integer(), binary()) :: {:ok, binary(), t()}
  def encode(%__MODULE__{} = codec, msg_code, payload) do
    # Snappy compress only after Hello exchange
    data =
      if codec.snappy do
        {:ok, compressed} = :snappyer.compress(payload)
        compressed
      else
        payload
      end

    # Build frame data: RLP(msg_code) || payload_data
    frame_data = ExRLP.encode(msg_code) <> data
    frame_size = byte_size(frame_data)

    # Header: frame-size (3 bytes) + RLP header data + padding to 16
    header_data = <<frame_size::big-unsigned-24, 0xC2, 0x80, 0x80>>
    header = pad_to_16(header_data)

    # Encrypt header
    header_ciphertext = :crypto.crypto_update(codec.enc_state, header)

    # Header MAC
    {header_mac, egress_mac} = Mac.compute(codec.egress_mac, header_ciphertext)

    # Pad frame data to 16-byte boundary
    padded_frame = pad_to_multiple_of_16(frame_data)

    # Encrypt frame
    frame_ciphertext = :crypto.crypto_update(codec.enc_state, padded_frame)

    # Frame MAC: feed ciphertext, then use current digest as seed
    egress_mac = Mac.update(egress_mac, frame_ciphertext)
    fmacseed = Mac.digest_16(egress_mac)
    {frame_mac, egress_mac} = Mac.compute(egress_mac, fmacseed)

    frame = header_ciphertext <> header_mac <> frame_ciphertext <> frame_mac

    {:ok, frame, %{codec | egress_mac: egress_mac}}
  end

  @doc """
  Decodes a frame from received bytes.
  Returns `{:ok, msg_code, payload, remaining_bytes, updated_codec}` or `{:error, reason}`.
  """
  @spec decode(t(), binary()) ::
          {:ok, non_neg_integer(), binary(), binary(), t()} | {:error, term()}
  def decode(%__MODULE__{} = codec, data) when byte_size(data) >= 32 do
    <<header_ciphertext::binary-size(16), header_mac::binary-size(16), rest::binary>> = data

    # Verify header MAC
    {expected_header_mac, ingress_mac} = Mac.compute(codec.ingress_mac, header_ciphertext)

    if header_mac != expected_header_mac do
      {:error, :invalid_header_mac}
    else
      # Decrypt header
      header = :crypto.crypto_update(codec.dec_state, header_ciphertext)
      <<frame_size::big-unsigned-24, _::binary>> = header

      # Frame is padded to 16-byte boundary
      padded_size = ceil_16(frame_size)
      total_needed = padded_size + 16

      if byte_size(rest) < total_needed do
        {:error, :incomplete_frame}
      else
        <<frame_ciphertext::binary-size(padded_size), frame_mac::binary-size(16),
          remaining::binary>> = rest

        # Verify frame MAC: feed ciphertext, then use current digest as seed
        ingress_mac = Mac.update(ingress_mac, frame_ciphertext)
        fmacseed = Mac.digest_16(ingress_mac)
        {expected_frame_mac, ingress_mac} = Mac.compute(ingress_mac, fmacseed)

        if frame_mac != expected_frame_mac do
          {:error, :invalid_frame_mac}
        else
          # Decrypt frame
          padded_frame = :crypto.crypto_update(codec.dec_state, frame_ciphertext)
          frame_data = binary_part(padded_frame, 0, frame_size)

          # Parse msg_code and decompress payload if snappy enabled
          {msg_code, raw_payload} = decode_msg_code(frame_data)

          if codec.snappy do
            case :snappyer.decompress(raw_payload) do
              {:ok, payload} ->
                {:ok, msg_code, payload, remaining, %{codec | ingress_mac: ingress_mac}}

              {:error, reason} ->
                {:error, {:snappy_decompress_failed, reason}}
            end
          else
            {:ok, msg_code, raw_payload, remaining, %{codec | ingress_mac: ingress_mac}}
          end
        end
      end
    end
  end

  def decode(_codec, _data), do: {:error, :insufficient_data}

  # --- Private helpers ---

  defp decode_msg_code(frame_data) do
    # RLP-encoded message code (0-255):
    # 0x80 = empty string = integer 0
    # 0x01-0x7F = single byte literal
    # 0x81 0xNN = single byte string for values >= 128
    case frame_data do
      <<0x80, rest::binary>> -> {0, rest}
      <<code, rest::binary>> when code < 0x80 -> {code, rest}
      <<0x81, code, rest::binary>> -> {code, rest}
    end
  end

  defp pad_to_16(data) when byte_size(data) >= 16, do: binary_part(data, 0, 16)

  defp pad_to_16(data) do
    pad_size = 16 - byte_size(data)
    data <> :binary.copy(<<0>>, pad_size)
  end

  defp pad_to_multiple_of_16(data) do
    rem = rem(byte_size(data), 16)

    if rem == 0 do
      data
    else
      data <> :binary.copy(<<0>>, 16 - rem)
    end
  end

  defp ceil_16(n) do
    case rem(n, 16) do
      0 -> n
      r -> n + (16 - r)
    end
  end
end
