defmodule EthNet.DiscV5.Packet do
  @moduledoc """
  DiscV5 packet encoding/decoding per the Node Discovery Protocol v5 spec.

  Packet structure:
  ```
  packet         = masking-iv || masked-header || message
  masking-iv     = random 16 bytes
  masked-header  = AES-CTR(masking-iv, dest-node-id[:16], header)
  header         = static-header || auth-data
  static-header  = protocol-id || version || flag || nonce || authdata-size
  ```

  Flags:
  - 0: Ordinary message (encrypted with session keys)
  - 1: WHOAREYOU (handshake challenge)
  - 2: Handshake message (includes auth data + encrypted message)

  Message types:
  - 1: PING
  - 2: PONG
  - 3: FINDNODE
  - 4: NODES
  - 5: TALKREQ
  - 6: TALKRESP
  """

  alias EthNet.DiscV5.Session

  @protocol_id "discv5"
  @version 0x0001

  # Message type constants
  @ping_type 1
  @pong_type 2
  @findnode_type 3
  @nodes_type 4
  @talkreq_type 5
  @talkresp_type 6

  # Packet flag constants
  @flag_message 0
  @flag_whoareyou 1
  @flag_handshake 2

  @type message_type :: :ping | :pong | :findnode | :nodes | :talkreq | :talkresp
  @type flag :: 0 | 1 | 2

  # --- Encoding ---

  @doc "Encodes a PING message payload."
  @spec encode_ping(non_neg_integer(), non_neg_integer()) :: binary()
  def encode_ping(request_id, enr_seq) do
    encode_message(@ping_type, [encode_integer(request_id), encode_integer(enr_seq)])
  end

  @doc "Encodes a PONG message payload."
  @spec encode_pong(non_neg_integer(), non_neg_integer(), :inet.ip_address(),
          :inet.port_number()) :: binary()
  def encode_pong(request_id, enr_seq, recipient_ip, recipient_port) do
    encode_message(@pong_type, [
      encode_integer(request_id),
      encode_integer(enr_seq),
      encode_ip(recipient_ip),
      encode_integer(recipient_port)
    ])
  end

  @doc "Encodes a FINDNODE message payload."
  @spec encode_findnode(non_neg_integer(), [non_neg_integer()]) :: binary()
  def encode_findnode(request_id, distances) do
    encoded_distances = Enum.map(distances, &encode_integer/1)
    encode_message(@findnode_type, [encode_integer(request_id), encoded_distances])
  end

  @doc "Encodes a NODES message payload."
  @spec encode_nodes(non_neg_integer(), non_neg_integer(), [binary()]) :: binary()
  def encode_nodes(request_id, total, enr_records) do
    encode_message(@nodes_type, [
      encode_integer(request_id),
      encode_integer(total),
      enr_records
    ])
  end

  @doc """
  Encodes an ordinary message packet (flag=0).

  Returns the full packet: masking-iv || masked-header || encrypted-message.
  """
  @spec encode_message_packet(binary(), <<_::256>>, <<_::96>>, Session.t()) ::
          {:ok, binary(), Session.t()} | {:error, atom()}
  def encode_message_packet(message, dest_node_id, nonce, session) do
    masking_iv = :crypto.strong_rand_bytes(16)

    # auth-data for ordinary message is just the 32-byte source node ID hash
    src_id = session.node_id
    auth_data = src_id
    authdata_size = byte_size(auth_data)

    static_header = encode_static_header(@flag_message, nonce, authdata_size)
    header = static_header <> auth_data

    # Encrypt message with the header nonce (same nonce goes in packet header and AES-GCM)
    case Session.encrypt_with_nonce(session, message, header, nonce) do
      {:ok, encrypted_message} ->
        masked_header = mask_header(masking_iv, dest_node_id, header)
        packet = masking_iv <> masked_header <> encrypted_message
        {:ok, packet, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Encodes a WHOAREYOU packet (flag=1).

  WHOAREYOU is sent as a challenge when we receive an unrecognized packet.
  Auth data contains: id-nonce (16 bytes) || enr-seq (8 bytes).
  """
  @spec encode_whoareyou(<<_::256>>, <<_::96>>, <<_::128>>, non_neg_integer()) :: binary()
  def encode_whoareyou(dest_node_id, nonce, id_nonce, enr_seq) do
    masking_iv = :crypto.strong_rand_bytes(16)
    auth_data = id_nonce <> <<enr_seq::unsigned-big-64>>
    authdata_size = byte_size(auth_data)

    static_header = encode_static_header(@flag_whoareyou, nonce, authdata_size)
    header = static_header <> auth_data

    masked_header = mask_header(masking_iv, dest_node_id, header)
    masking_iv <> masked_header
  end

  @doc """
  Encodes a handshake message packet (flag=2).

  Auth data contains: src-id (32 bytes) || sig-size (1) || eph-key-size (1) ||
  id-signature || ephemeral-pubkey || [enr-record].
  """
  @spec encode_handshake_packet(
          binary(),
          <<_::256>>,
          <<_::96>>,
          <<_::256>>,
          binary(),
          binary(),
          binary() | nil,
          Session.t()
        ) :: {:ok, binary(), Session.t()} | {:error, atom()}
  def encode_handshake_packet(
        message,
        dest_node_id,
        nonce,
        src_id,
        id_signature,
        ephemeral_pubkey,
        enr_record,
        session
      ) do
    masking_iv = :crypto.strong_rand_bytes(16)

    sig_size = byte_size(id_signature)
    eph_key_size = byte_size(ephemeral_pubkey)

    auth_data =
      src_id <>
        <<sig_size::8, eph_key_size::8>> <>
        id_signature <>
        ephemeral_pubkey <>
        (enr_record || <<>>)

    authdata_size = byte_size(auth_data)

    static_header = encode_static_header(@flag_handshake, nonce, authdata_size)
    header = static_header <> auth_data

    case Session.encrypt_with_nonce(session, message, header, nonce) do
      {:ok, encrypted_message} ->
        masked_header = mask_header(masking_iv, dest_node_id, header)
        packet = masking_iv <> masked_header <> encrypted_message
        {:ok, packet, session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Decoding ---

  @doc """
  Decodes a DiscV5 packet, returning the flag, header data, and message body.

  The local node ID is needed to unmask the header.
  """
  @spec decode(binary(), <<_::256>>) ::
          {:ok, {flag(), map()}} | {:error, atom()}
  def decode(<<masking_iv::binary-size(16), rest::binary>>, local_node_id)
      when byte_size(rest) >= 23 do
    # Unmask just the static header first (23 bytes)
    static_header_size = 23
    unmasked_static = unmask_header(masking_iv, local_node_id, rest, static_header_size)

    case parse_static_header(unmasked_static) do
      {:ok, flag, nonce, authdata_size} ->
        # Now unmask the full header (static + auth data)
        full_header_size = static_header_size + authdata_size

        if byte_size(rest) < full_header_size do
          {:error, :packet_too_short}
        else
          full_unmasked = unmask_header(masking_iv, local_node_id, rest, full_header_size)
          <<_static::binary-size(static_header_size), auth_data::binary>> = full_unmasked
          encrypted_message = binary_part(rest, full_header_size, byte_size(rest) - full_header_size)

          parse_by_flag(flag, nonce, auth_data, encrypted_message, full_unmasked)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def decode(_, _), do: {:error, :packet_too_short}

  @doc "Decodes a message payload (after decryption)."
  @spec decode_message(binary()) :: {:ok, {message_type(), map()}} | {:error, atom()}
  def decode_message(<<type, rlp_data::binary>>) do
    decode_message_type(type, rlp_data)
  end

  def decode_message(_), do: {:error, :empty_message}

  # --- Private helpers ---

  defp encode_static_header(flag, nonce, authdata_size) do
    @protocol_id <>
      <<@version::unsigned-big-16>> <>
      <<flag::8>> <>
      nonce <>
      <<authdata_size::unsigned-big-16>>
  end

  defp parse_static_header(data) do
    case data do
      <<@protocol_id, version::unsigned-big-16, flag::8, nonce::binary-size(12),
        authdata_size::unsigned-big-16>> ->
        if version == @version do
          {:ok, flag, nonce, authdata_size}
        else
          {:error, :unsupported_version}
        end

      _ ->
        {:error, :invalid_static_header}
    end
  end

  defp parse_by_flag(@flag_message, nonce, auth_data, encrypted_message, header) do
    # auth_data = src-id (32 bytes)
    if byte_size(auth_data) >= 32 do
      <<src_id::binary-size(32), _::binary>> = auth_data

      {:ok,
       {@flag_message,
        %{
          src_id: src_id,
          nonce: nonce,
          encrypted_message: encrypted_message,
          header: header
        }}}
    else
      {:error, :invalid_auth_data}
    end
  end

  defp parse_by_flag(@flag_whoareyou, nonce, auth_data, _encrypted_message, _header) do
    # auth_data = id-nonce (16 bytes) || enr-seq (8 bytes)
    case auth_data do
      <<id_nonce::binary-size(16), enr_seq::unsigned-big-64>> ->
        {:ok,
         {@flag_whoareyou,
          %{
            nonce: nonce,
            id_nonce: id_nonce,
            enr_seq: enr_seq
          }}}

      _ ->
        {:error, :invalid_whoareyou_auth}
    end
  end

  defp parse_by_flag(@flag_handshake, nonce, auth_data, encrypted_message, header) do
    # auth_data = src-id (32) || sig-size (1) || eph-key-size (1) ||
    #             id-signature || ephemeral-pubkey || [enr-record]
    case auth_data do
      <<src_id::binary-size(32), sig_size::8, eph_key_size::8, rest::binary>> ->
        if byte_size(rest) >= sig_size + eph_key_size do
          <<id_signature::binary-size(sig_size),
            ephemeral_pubkey::binary-size(eph_key_size),
            enr_data::binary>> = rest

          {:ok,
           {@flag_handshake,
            %{
              src_id: src_id,
              nonce: nonce,
              id_signature: id_signature,
              ephemeral_pubkey: ephemeral_pubkey,
              enr_data: enr_data,
              encrypted_message: encrypted_message,
              header: header
            }}}
        else
          {:error, :invalid_handshake_auth}
        end

      _ ->
        {:error, :invalid_handshake_auth}
    end
  end

  defp parse_by_flag(_, _nonce, _auth_data, _encrypted_message, _header) do
    {:error, :unknown_flag}
  end

  defp decode_message_type(@ping_type, rlp_data) do
    [request_id, enr_seq] = ExRLP.decode(rlp_data)

    {:ok,
     {:ping,
      %{
        request_id: decode_integer(request_id),
        enr_seq: decode_integer(enr_seq)
      }}}
  rescue
    _ -> {:error, :invalid_ping}
  end

  defp decode_message_type(@pong_type, rlp_data) do
    [request_id, enr_seq, recipient_ip, recipient_port] = ExRLP.decode(rlp_data)

    {:ok,
     {:pong,
      %{
        request_id: decode_integer(request_id),
        enr_seq: decode_integer(enr_seq),
        recipient_ip: decode_ip(recipient_ip),
        recipient_port: decode_integer(recipient_port)
      }}}
  rescue
    _ -> {:error, :invalid_pong}
  end

  defp decode_message_type(@findnode_type, rlp_data) do
    [request_id, distances] = ExRLP.decode(rlp_data)

    {:ok,
     {:findnode,
      %{
        request_id: decode_integer(request_id),
        distances: Enum.map(distances, &decode_integer/1)
      }}}
  rescue
    _ -> {:error, :invalid_findnode}
  end

  defp decode_message_type(@nodes_type, rlp_data) do
    [request_id, total, enr_records] = ExRLP.decode(rlp_data)

    {:ok,
     {:nodes,
      %{
        request_id: decode_integer(request_id),
        total: decode_integer(total),
        enr_records: enr_records
      }}}
  rescue
    _ -> {:error, :invalid_nodes}
  end

  defp decode_message_type(@talkreq_type, rlp_data) do
    [request_id, protocol, request] = ExRLP.decode(rlp_data)

    {:ok,
     {:talkreq,
      %{
        request_id: decode_integer(request_id),
        protocol: protocol,
        request: request
      }}}
  rescue
    _ -> {:error, :invalid_talkreq}
  end

  defp decode_message_type(@talkresp_type, rlp_data) do
    [request_id, response] = ExRLP.decode(rlp_data)

    {:ok,
     {:talkresp,
      %{
        request_id: decode_integer(request_id),
        response: response
      }}}
  rescue
    _ -> {:error, :invalid_talkresp}
  end

  defp decode_message_type(_, _), do: {:error, :unknown_message_type}

  defp encode_message(type, fields) do
    <<type>> <> ExRLP.encode(fields)
  end

  defp mask_header(masking_iv, dest_node_id, header) do
    # Use first 16 bytes of dest_node_id as AES-CTR key
    key = binary_part(dest_node_id, 0, 16)
    :crypto.crypto_one_time(:aes_128_ctr, key, masking_iv, header, true)
  end

  defp unmask_header(masking_iv, local_node_id, data, length) do
    key = binary_part(local_node_id, 0, 16)
    masked = binary_part(data, 0, length)
    :crypto.crypto_one_time(:aes_128_ctr, key, masking_iv, masked, false)
  end

  defp encode_ip({a, b, c, d}), do: <<a, b, c, d>>

  defp decode_ip(<<a, b, c, d>>), do: {a, b, c, d}
  defp decode_ip(_), do: {0, 0, 0, 0}

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
end
