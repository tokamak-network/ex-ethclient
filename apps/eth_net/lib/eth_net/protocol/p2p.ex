defmodule EthNet.Protocol.P2P do
  @moduledoc """
  DevP2P base protocol messages: Hello, Disconnect, Ping, Pong.

  Message codes:
  - 0x00: Hello
  - 0x01: Disconnect
  - 0x02: Ping
  - 0x03: Pong
  """

  @hello_code 0x00
  @disconnect_code 0x01
  @ping_code 0x02
  @pong_code 0x03

  @p2p_version 5
  @client_id "ex_ethclient/0.1.0"

  # Disconnect reasons
  @disconnect_reasons %{
    0x00 => :requested,
    0x01 => :tcp_error,
    0x02 => :breach_of_protocol,
    0x03 => :useless_peer,
    0x04 => :too_many_peers,
    0x05 => :already_connected,
    0x06 => :incompatible_version,
    0x07 => :null_node_identity,
    0x08 => :client_quitting,
    0x09 => :unexpected_identity,
    0x0A => :same_identity,
    0x0B => :ping_timeout,
    0x10 => :subprotocol_error
  }

  # --- Encoding ---

  @doc "Encodes a Hello message."
  @spec encode_hello(binary(), non_neg_integer()) :: {non_neg_integer(), binary()}
  def encode_hello(node_id, listen_port \\ 0) do
    # Advertise eth/66, eth/67, and eth/68 to maximize peer compatibility
    capabilities = [["eth", 66], ["eth", 67], ["eth", 68]]

    payload =
      ExRLP.encode([
        @p2p_version,
        @client_id,
        capabilities,
        listen_port,
        node_id
      ])

    {@hello_code, payload}
  end

  @doc "Encodes a Disconnect message."
  def encode_disconnect(reason \\ :requested) do
    code = reason_to_code(reason)
    payload = ExRLP.encode([code])
    {@disconnect_code, payload}
  end

  @doc "Encodes a Ping message."
  def encode_ping do
    {@ping_code, ExRLP.encode([])}
  end

  @doc "Encodes a Pong message."
  def encode_pong do
    {@pong_code, ExRLP.encode([])}
  end

  # --- Decoding ---

  @doc "Decodes a P2P message by code."
  def decode(@hello_code, payload) do
    [version, client_id, capabilities, listen_port, node_id | _] = ExRLP.decode(payload)

    caps =
      Enum.map(capabilities, fn [name, ver] ->
        {name, decode_integer(ver)}
      end)

    {:hello,
     %{
       version: decode_integer(version),
       client_id: client_id,
       capabilities: caps,
       listen_port: decode_integer(listen_port),
       node_id: node_id
     }}
  end

  def decode(@disconnect_code, payload) do
    case ExRLP.decode(payload) do
      [reason_bin | _] ->
        code = decode_integer(reason_bin)
        {:disconnect, Map.get(@disconnect_reasons, code, {:unknown, code})}

      _ ->
        {:disconnect, :unknown}
    end
  end

  def decode(@ping_code, _payload), do: :ping
  def decode(@pong_code, _payload), do: :pong
  def decode(code, _payload), do: {:unknown_p2p, code}

  @doc "Returns true if the message code is a P2P base protocol message."
  def p2p_message?(code), do: code in [@hello_code, @disconnect_code, @ping_code, @pong_code]

  @doc "Message code constants."
  def hello_code, do: @hello_code
  def disconnect_code, do: @disconnect_code
  def ping_code, do: @ping_code
  def pong_code, do: @pong_code

  defp reason_to_code(:requested), do: 0x00
  defp reason_to_code(:tcp_error), do: 0x01
  defp reason_to_code(:breach_of_protocol), do: 0x02
  defp reason_to_code(:useless_peer), do: 0x03
  defp reason_to_code(:too_many_peers), do: 0x04
  defp reason_to_code(:already_connected), do: 0x05
  defp reason_to_code(:incompatible_version), do: 0x06
  defp reason_to_code(:client_quitting), do: 0x08
  defp reason_to_code(:subprotocol_error), do: 0x10
  defp reason_to_code(code) when is_integer(code), do: code

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
  defp decode_integer(n) when is_integer(n), do: n
end
