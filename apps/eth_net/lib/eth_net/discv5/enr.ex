defmodule EthNet.DiscV5.ENR do
  @moduledoc """
  Ethereum Node Records (EIP-778) for DiscV5.

  An ENR is a signed, versioned record containing node metadata.
  Format: `[signature, seq, k1, v1, k2, v2, ...]`
  Keys are sorted lexicographically. The identity scheme "v4"
  uses secp256k1 signing over the content (everything after the signature).
  """

  alias EthCrypto.{Hash, Signature}

  @type t :: %__MODULE__{
          signature: binary(),
          seq: non_neg_integer(),
          pairs: %{String.t() => binary()},
          raw: binary() | nil
        }

  @enforce_keys [:seq, :pairs]
  defstruct [:signature, :seq, :pairs, :raw]

  @doc "Creates a new ENR record signed with the given private key."
  @spec new(non_neg_integer(), :inet.ip_address(), :inet.port_number(), :inet.port_number(),
          <<_::256>>) :: {:ok, t()} | {:error, atom()}
  def new(seq, ip, udp_port, tcp_port, private_key) do
    {:ok, public_key} = Signature.public_key_from_private(private_key)
    compressed = compress_public_key(public_key)

    pairs = %{
      "id" => "v4",
      "secp256k1" => compressed,
      "ip" => encode_ip(ip),
      "udp" => encode_uint16(udp_port),
      "tcp" => encode_uint16(tcp_port)
    }

    content = encode_content(seq, pairs)
    content_hash = Hash.keccak256(content)

    case Signature.sign(content_hash, private_key) do
      {:ok, {r, s, _recovery_id}} ->
        sig = r <> s
        record = %__MODULE__{signature: sig, seq: seq, pairs: pairs}
        {:ok, record}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Encodes an ENR to RLP binary."
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = enr) do
    elements = [enr.signature, encode_integer(enr.seq)] ++ sorted_pair_list(enr.pairs)
    ExRLP.encode(elements)
  end

  @doc "Decodes an ENR from RLP binary."
  @spec decode(binary()) :: {:ok, t()} | {:error, atom()}
  def decode(data) when is_binary(data) do
    case ExRLP.decode(data) do
      [signature | [seq_bin | kv_list]] when is_binary(signature) ->
        seq = decode_integer(seq_bin)
        pairs = decode_pairs(kv_list)

        {:ok,
         %__MODULE__{
           signature: signature,
           seq: seq,
           pairs: pairs,
           raw: data
         }}

      _ ->
        {:error, :invalid_enr}
    end
  rescue
    _ -> {:error, :invalid_enr}
  end

  @doc "Returns the node ID (keccak256 of the compressed public key) from an ENR."
  @spec node_id(t()) :: {:ok, <<_::256>>} | {:error, atom()}
  def node_id(%__MODULE__{pairs: pairs}) do
    case Map.get(pairs, "secp256k1") do
      nil -> {:error, :no_public_key}
      pubkey -> {:ok, Hash.keccak256(pubkey)}
    end
  end

  @doc "Returns the IP address from an ENR."
  @spec ip(t()) :: {:ok, :inet.ip_address()} | {:error, atom()}
  def ip(%__MODULE__{pairs: pairs}) do
    case Map.get(pairs, "ip") do
      <<a, b, c, d>> -> {:ok, {a, b, c, d}}
      _ -> {:error, :no_ip}
    end
  end

  @doc "Returns the UDP port from an ENR."
  @spec udp_port(t()) :: {:ok, :inet.port_number()} | {:error, atom()}
  def udp_port(%__MODULE__{pairs: pairs}) do
    case Map.get(pairs, "udp") do
      bin when is_binary(bin) and byte_size(bin) > 0 -> {:ok, decode_integer(bin)}
      _ -> {:error, :no_udp_port}
    end
  end

  @doc "Returns the TCP port from an ENR."
  @spec tcp_port(t()) :: {:ok, :inet.port_number()} | {:error, atom()}
  def tcp_port(%__MODULE__{pairs: pairs}) do
    case Map.get(pairs, "tcp") do
      bin when is_binary(bin) and byte_size(bin) > 0 -> {:ok, decode_integer(bin)}
      _ -> {:error, :no_tcp_port}
    end
  end

  @doc "Returns the ENR sequence number."
  @spec seq(t()) :: non_neg_integer()
  def seq(%__MODULE__{seq: seq}), do: seq

  # --- Private helpers ---

  defp encode_content(seq, pairs) do
    elements = [encode_integer(seq)] ++ sorted_pair_list(pairs)
    ExRLP.encode(elements)
  end

  defp sorted_pair_list(pairs) do
    pairs
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.flat_map(fn {k, v} -> [k, v] end)
  end

  defp decode_pairs(kv_list), do: decode_pairs(kv_list, %{})

  defp decode_pairs([], acc), do: acc
  defp decode_pairs([k, v | rest], acc), do: decode_pairs(rest, Map.put(acc, k, v))
  defp decode_pairs([_], acc), do: acc

  defp encode_ip({a, b, c, d}), do: <<a, b, c, d>>

  defp encode_uint16(n) when is_integer(n) and n >= 0, do: :binary.encode_unsigned(n)

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)

  defp compress_public_key(<<_::binary-size(64)>> = uncompressed) do
    # Compressed public key: 0x02 or 0x03 prefix + 32-byte X coordinate
    <<x::binary-size(32), _y::binary-size(32)>> = uncompressed
    y_int = :binary.decode_unsigned(binary_part(uncompressed, 32, 32))
    prefix = if rem(y_int, 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end
end
