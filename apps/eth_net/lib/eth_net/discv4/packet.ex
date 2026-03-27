defmodule EthNet.DiscV4.Packet do
  @moduledoc """
  DiscV4 packet encoding/decoding.

  Packet format: `hash(32) || signature(65) || type(1) || rlp(data)`
  - hash = keccak256(signature || type || rlp_data)
  - signature = secp256k1_sign(keccak256(type || rlp_data), private_key)
  """

  alias EthCrypto.{Hash, Signature}

  @ping_type 1
  @pong_type 2
  @findnode_type 3
  @neighbours_type 4

  @discv4_version 4

  # --- Encoding ---

  @doc "Encodes a PING packet."
  @spec encode_ping(:inet.ip_address(), non_neg_integer(), non_neg_integer(), :inet.ip_address(), non_neg_integer(), non_neg_integer(), binary()) :: {:ok, binary()}
  def encode_ping(from_ip, from_udp, from_tcp, to_ip, to_udp, to_tcp, private_key) do
    expiration = expiration_timestamp()

    data =
      ExRLP.encode([
        @discv4_version,
        encode_endpoint(from_ip, from_udp, from_tcp),
        encode_endpoint(to_ip, to_udp, to_tcp),
        encode_integer(expiration)
      ])

    sign_and_wrap(@ping_type, data, private_key)
  end

  @doc "Encodes a PONG packet."
  @spec encode_pong(:inet.ip_address(), non_neg_integer(), non_neg_integer(), binary(), binary()) :: {:ok, binary()}
  def encode_pong(to_ip, to_udp, to_tcp, ping_hash, private_key) do
    expiration = expiration_timestamp()

    data =
      ExRLP.encode([
        encode_endpoint(to_ip, to_udp, to_tcp),
        ping_hash,
        encode_integer(expiration)
      ])

    sign_and_wrap(@pong_type, data, private_key)
  end

  @doc "Encodes a FINDNODE packet."
  @spec encode_findnode(binary(), binary()) :: {:ok, binary()}
  def encode_findnode(target_id, private_key) do
    expiration = expiration_timestamp()

    data =
      ExRLP.encode([
        target_id,
        encode_integer(expiration)
      ])

    sign_and_wrap(@findnode_type, data, private_key)
  end

  @doc "Encodes a NEIGHBOURS packet."
  @spec encode_neighbours([EthNet.DiscV4.Node.t()], binary()) :: {:ok, binary()}
  def encode_neighbours(nodes, private_key) do
    expiration = expiration_timestamp()

    node_list =
      Enum.map(nodes, fn node ->
        {a, b, c, d} = node.ip

        [
          <<a, b, c, d>>,
          encode_integer(node.udp_port),
          encode_integer(node.tcp_port || 0),
          node.id
        ]
      end)

    data = ExRLP.encode([node_list, encode_integer(expiration)])
    sign_and_wrap(@neighbours_type, data, private_key)
  end

  # --- Decoding ---

  @doc """
  Decodes a DiscV4 packet, returning `{:ok, {type, data, node_id, hash}}` or `{:error, reason}`.
  """
  @spec decode(binary()) :: {:ok, {atom(), map(), binary(), binary()}} | {:error, term()}
  def decode(
        <<hash::binary-size(32), sig_r::binary-size(32), sig_s::binary-size(32), recovery_id,
          type, rlp_data::binary>>
      ) do
    signed_data = <<sig_r::binary, sig_s::binary, recovery_id, type, rlp_data::binary>>
    expected_hash = Hash.keccak256(signed_data)

    if hash != expected_hash do
      {:error, :invalid_hash}
    else
      sign_payload = <<type, rlp_data::binary>>
      sign_hash = Hash.keccak256(sign_payload)

      case Signature.recover(sign_hash, sig_r, sig_s, recovery_id) do
        {:ok, node_id} ->
          decode_type(type, rlp_data, node_id, hash)

        {:error, reason} ->
          {:error, {:signature_recovery_failed, reason}}
      end
    end
  end

  def decode(_), do: {:error, :invalid_packet_size}

  # --- Private helpers ---

  defp sign_and_wrap(type, rlp_data, private_key) do
    sign_payload = <<type, rlp_data::binary>>
    sign_hash = Hash.keccak256(sign_payload)

    {:ok, {r, s, recovery_id}} = Signature.sign(sign_hash, private_key)

    signed_data = <<r::binary, s::binary, recovery_id, type, rlp_data::binary>>
    hash = Hash.keccak256(signed_data)

    {:ok, hash <> signed_data}
  end

  defp decode_type(@ping_type, rlp_data, node_id, hash) do
    [version, from, to, expiration | _] = ExRLP.decode(rlp_data)

    {:ok,
     {:ping,
      %{
        version: decode_integer(version),
        from: decode_endpoint(from),
        to: decode_endpoint(to),
        expiration: decode_integer(expiration)
      }, node_id, hash}}
  end

  defp decode_type(@pong_type, rlp_data, node_id, hash) do
    [to, ping_hash, expiration | _] = ExRLP.decode(rlp_data)

    {:ok,
     {:pong,
      %{
        to: decode_endpoint(to),
        ping_hash: ping_hash,
        expiration: decode_integer(expiration)
      }, node_id, hash}}
  end

  defp decode_type(@findnode_type, rlp_data, node_id, hash) do
    [target, expiration | _] = ExRLP.decode(rlp_data)

    {:ok,
     {:findnode,
      %{
        target: target,
        expiration: decode_integer(expiration)
      }, node_id, hash}}
  end

  defp decode_type(@neighbours_type, rlp_data, node_id, hash) do
    [node_list, expiration | _] = ExRLP.decode(rlp_data)

    nodes =
      node_list
      |> Enum.flat_map(fn
        [ip_bin, udp_port_bin, tcp_port_bin, id] ->
          case decode_ip(ip_bin) do
            nil ->
              []

            ip ->
              [
                %EthNet.DiscV4.Node{
                  id: id,
                  ip: ip,
                  udp_port: decode_integer(udp_port_bin),
                  tcp_port: decode_integer(tcp_port_bin)
                }
              ]
          end

        _ ->
          []
      end)

    {:ok,
     {:neighbours,
      %{
        nodes: nodes,
        expiration: decode_integer(expiration)
      }, node_id, hash}}
  end

  defp decode_type(type, _rlp_data, _node_id, _hash) do
    {:error, {:unknown_packet_type, type}}
  end

  defp encode_endpoint(ip, udp_port, tcp_port) do
    {a, b, c, d} = ip
    [<<a, b, c, d>>, encode_integer(udp_port), encode_integer(tcp_port)]
  end

  defp decode_endpoint([ip_bin, udp_port_bin, tcp_port_bin]) do
    %{
      ip: decode_ip(ip_bin),
      udp_port: decode_integer(udp_port_bin),
      tcp_port: decode_integer(tcp_port_bin)
    }
  end

  defp decode_ip(<<a, b, c, d>>), do: {a, b, c, d}
  # IPv6-mapped IPv4: ::ffff:a.b.c.d
  defp decode_ip(<<0::80, 0xFFFF::16, a, b, c, d>>), do: {a, b, c, d}
  defp decode_ip(<<>>), do: {0, 0, 0, 0}
  defp decode_ip(_), do: nil

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)

  defp expiration_timestamp do
    System.system_time(:second) + 20
  end
end
