defmodule EthNet.DiscV4.Node do
  @moduledoc """
  Represents a node in the DiscV4 protocol.
  Node ID is the 64-byte uncompressed public key.
  Distance is computed as XOR of keccak256(id).
  """

  @enforce_keys [:id, :ip, :udp_port]
  defstruct [:id, :ip, :udp_port, :tcp_port, :last_pong, :last_ping_hash]

  @type t :: %__MODULE__{
          id: <<_::512>>,
          ip: :inet.ip_address(),
          udp_port: :inet.port_number(),
          tcp_port: :inet.port_number() | nil,
          last_pong: integer() | nil,
          last_ping_hash: binary() | nil
        }

  @doc "Computes the log2 XOR distance between two node IDs (0..255)."
  @spec log_distance(<<_::512>>, <<_::512>>) :: non_neg_integer()
  def log_distance(id_a, id_b) do
    hash_a = EthCrypto.Hash.keccak256(id_a)
    hash_b = EthCrypto.Hash.keccak256(id_b)
    xor_distance = :crypto.exor(hash_a, hash_b)
    leading_zeros = count_leading_zeros(xor_distance)
    255 - leading_zeros
  end

  @doc "Parses an enode URL into a Node struct."
  @spec from_enode(String.t()) :: {:ok, t()} | {:error, term()}
  def from_enode("enode://" <> rest) do
    case String.split(rest, "@") do
      [id_hex, host_port] ->
        case String.split(host_port, ":") do
          [host, port_str] ->
            with {:ok, id} <- decode_hex(id_hex),
                 true <- byte_size(id) == 64,
                 {port, ""} <- Integer.parse(port_str),
                 {:ok, ip} <- parse_ip(host) do
              {:ok, %__MODULE__{id: id, ip: ip, udp_port: port, tcp_port: port}}
            else
              _ -> {:error, :invalid_enode}
            end

          _ ->
            {:error, :invalid_enode}
        end

      _ ->
        {:error, :invalid_enode}
    end
  end

  def from_enode(_), do: {:error, :invalid_enode}

  defp decode_hex(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, _} = ok -> ok
      :error -> {:error, :invalid_hex}
    end
  end

  defp parse_ip(host) do
    host
    |> String.to_charlist()
    |> :inet.parse_address()
  end

  defp count_leading_zeros(<<>>), do: 0

  defp count_leading_zeros(<<0, rest::binary>>), do: 8 + count_leading_zeros(rest)

  defp count_leading_zeros(<<byte, _::binary>>) do
    # Count leading zero bits in the first non-zero byte
    cond do
      byte >= 128 -> 0
      byte >= 64 -> 1
      byte >= 32 -> 2
      byte >= 16 -> 3
      byte >= 8 -> 4
      byte >= 4 -> 5
      byte >= 2 -> 6
      true -> 7
    end
  end
end
