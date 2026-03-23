defmodule EthNet.Protocol.Snap1 do
  @moduledoc """
  snap/1 state sync protocol message encoding/decoding.

  The snap/1 protocol operates on capability offset 0x00 (separate from eth).
  It provides 8 message types for efficient state synchronization:

  - 0x00: GetAccountRange   — request accounts in a range
  - 0x01: AccountRange      — response with accounts + proof
  - 0x02: GetStorageRanges  — request storage for accounts
  - 0x03: StorageRanges     — response with storage + proof
  - 0x04: GetByteCodes      — request contract bytecodes
  - 0x05: ByteCodes         — response with bytecodes
  - 0x06: GetTrieNodes      — request trie nodes by path
  - 0x07: TrieNodes         — response with trie nodes
  """

  # Message codes (snap/1 has its own capability offset, starts at 0x00)
  @get_account_range 0x00
  @account_range 0x01
  @get_storage_ranges 0x02
  @storage_ranges 0x03
  @get_byte_codes 0x04
  @byte_codes 0x05
  @get_trie_nodes 0x06
  @trie_nodes 0x07

  # --- Message code accessors ---

  @doc "Returns the GetAccountRange message code."
  @spec get_account_range_code() :: non_neg_integer()
  def get_account_range_code, do: @get_account_range

  @doc "Returns the AccountRange message code."
  @spec account_range_code() :: non_neg_integer()
  def account_range_code, do: @account_range

  @doc "Returns the GetStorageRanges message code."
  @spec get_storage_ranges_code() :: non_neg_integer()
  def get_storage_ranges_code, do: @get_storage_ranges

  @doc "Returns the StorageRanges message code."
  @spec storage_ranges_code() :: non_neg_integer()
  def storage_ranges_code, do: @storage_ranges

  @doc "Returns the GetByteCodes message code."
  @spec get_byte_codes_code() :: non_neg_integer()
  def get_byte_codes_code, do: @get_byte_codes

  @doc "Returns the ByteCodes message code."
  @spec byte_codes_code() :: non_neg_integer()
  def byte_codes_code, do: @byte_codes

  @doc "Returns the GetTrieNodes message code."
  @spec get_trie_nodes_code() :: non_neg_integer()
  def get_trie_nodes_code, do: @get_trie_nodes

  @doc "Returns the TrieNodes message code."
  @spec trie_nodes_code() :: non_neg_integer()
  def trie_nodes_code, do: @trie_nodes

  # --- GetAccountRange ---

  @doc """
  Encodes a GetAccountRange message.

  Format: [request_id, root_hash, starting_hash, limit_hash, response_bytes]
  """
  @spec encode_get_account_range(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer()
        ) ::
          {non_neg_integer(), binary()}
  def encode_get_account_range(request_id, root_hash, start_hash, limit_hash, response_bytes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        root_hash,
        start_hash,
        limit_hash,
        encode_integer(response_bytes)
      ])

    {@get_account_range, payload}
  end

  @doc "Decodes a GetAccountRange message payload."
  @spec decode_get_account_range(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_account_range(payload) do
    case ExRLP.decode(payload) do
      [request_id, root_hash, start_hash, limit_hash, response_bytes] ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           root_hash: root_hash,
           start_hash: start_hash,
           limit_hash: limit_hash,
           response_bytes: decode_integer(response_bytes)
         }}

      _ ->
        {:error, :invalid_get_account_range}
    end
  rescue
    _ -> {:error, :invalid_get_account_range}
  end

  # --- AccountRange ---

  @doc """
  Encodes an AccountRange message.

  Format: [request_id, accounts, proof]
  accounts: [[hash, nonce, balance, storage_root, code_hash], ...]
  proof: [node1, node2, ...] (Merkle proof nodes)
  """
  @spec encode_account_range(non_neg_integer(), list(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_account_range(request_id, accounts, proof) do
    encoded_accounts =
      Enum.map(accounts, fn {hash, nonce, balance, storage_root, code_hash} ->
        [hash, encode_integer(nonce), encode_integer(balance), storage_root, code_hash]
      end)

    payload =
      ExRLP.encode([
        encode_integer(request_id),
        encoded_accounts,
        proof
      ])

    {@account_range, payload}
  end

  @doc "Decodes an AccountRange message payload."
  @spec decode_account_range(binary()) :: {:ok, map()} | {:error, term()}
  def decode_account_range(payload) do
    case ExRLP.decode(payload) do
      [request_id, accounts_rlp, proof] when is_list(accounts_rlp) and is_list(proof) ->
        accounts =
          Enum.map(accounts_rlp, fn [hash, nonce, balance, storage_root, code_hash] ->
            {hash, decode_integer(nonce), decode_integer(balance), storage_root, code_hash}
          end)

        {:ok,
         %{
           request_id: decode_integer(request_id),
           accounts: accounts,
           proof: proof
         }}

      _ ->
        {:error, :invalid_account_range}
    end
  rescue
    _ -> {:error, :invalid_account_range}
  end

  # --- GetStorageRanges ---

  @doc """
  Encodes a GetStorageRanges message.

  Format: [request_id, root_hash, account_hashes, starting_hash, limit_hash, response_bytes]
  """
  @spec encode_get_storage_ranges(
          non_neg_integer(),
          binary(),
          [binary()],
          binary(),
          binary(),
          non_neg_integer()
        ) :: {non_neg_integer(), binary()}
  def encode_get_storage_ranges(request_id, root, accounts, start_hash, limit_hash, bytes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        root,
        accounts,
        start_hash,
        limit_hash,
        encode_integer(bytes)
      ])

    {@get_storage_ranges, payload}
  end

  @doc "Decodes a GetStorageRanges message payload."
  @spec decode_get_storage_ranges(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_storage_ranges(payload) do
    case ExRLP.decode(payload) do
      [request_id, root, accounts, start_hash, limit_hash, bytes]
      when is_list(accounts) ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           root_hash: root,
           account_hashes: accounts,
           start_hash: start_hash,
           limit_hash: limit_hash,
           response_bytes: decode_integer(bytes)
         }}

      _ ->
        {:error, :invalid_get_storage_ranges}
    end
  rescue
    _ -> {:error, :invalid_get_storage_ranges}
  end

  # --- StorageRanges ---

  @doc """
  Encodes a StorageRanges message.

  Format: [request_id, slots, proof]
  slots: [[[hash, value], ...], ...]  (per account)
  proof: [node1, node2, ...] (Merkle proof nodes)
  """
  @spec encode_storage_ranges(non_neg_integer(), list(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_storage_ranges(request_id, slots, proof) do
    encoded_slots =
      Enum.map(slots, fn account_slots ->
        Enum.map(account_slots, fn {hash, value} ->
          [hash, value]
        end)
      end)

    payload =
      ExRLP.encode([
        encode_integer(request_id),
        encoded_slots,
        proof
      ])

    {@storage_ranges, payload}
  end

  @doc "Decodes a StorageRanges message payload."
  @spec decode_storage_ranges(binary()) :: {:ok, map()} | {:error, term()}
  def decode_storage_ranges(payload) do
    case ExRLP.decode(payload) do
      [request_id, slots_rlp, proof] when is_list(slots_rlp) and is_list(proof) ->
        slots =
          Enum.map(slots_rlp, fn account_slots ->
            Enum.map(account_slots, fn [hash, value] ->
              {hash, value}
            end)
          end)

        {:ok,
         %{
           request_id: decode_integer(request_id),
           slots: slots,
           proof: proof
         }}

      _ ->
        {:error, :invalid_storage_ranges}
    end
  rescue
    _ -> {:error, :invalid_storage_ranges}
  end

  # --- GetByteCodes ---

  @doc """
  Encodes a GetByteCodes message.

  Format: [request_id, hashes, response_bytes]
  """
  @spec encode_get_byte_codes(non_neg_integer(), [binary()], non_neg_integer()) ::
          {non_neg_integer(), binary()}
  def encode_get_byte_codes(request_id, hashes, bytes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        hashes,
        encode_integer(bytes)
      ])

    {@get_byte_codes, payload}
  end

  @doc "Decodes a GetByteCodes message payload."
  @spec decode_get_byte_codes(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_byte_codes(payload) do
    case ExRLP.decode(payload) do
      [request_id, hashes, bytes] when is_list(hashes) ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           hashes: hashes,
           response_bytes: decode_integer(bytes)
         }}

      _ ->
        {:error, :invalid_get_byte_codes}
    end
  rescue
    _ -> {:error, :invalid_get_byte_codes}
  end

  # --- ByteCodes ---

  @doc """
  Encodes a ByteCodes message.

  Format: [request_id, codes]
  """
  @spec encode_byte_codes(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_byte_codes(request_id, codes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        codes
      ])

    {@byte_codes, payload}
  end

  @doc "Decodes a ByteCodes message payload."
  @spec decode_byte_codes(binary()) :: {:ok, map()} | {:error, term()}
  def decode_byte_codes(payload) do
    case ExRLP.decode(payload) do
      [request_id, codes] when is_list(codes) ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           codes: codes
         }}

      _ ->
        {:error, :invalid_byte_codes}
    end
  rescue
    _ -> {:error, :invalid_byte_codes}
  end

  # --- GetTrieNodes ---

  @doc """
  Encodes a GetTrieNodes message.

  Format: [request_id, root_hash, paths, response_bytes]
  paths: [[account_path, storage_path1, storage_path2, ...], ...]
  """
  @spec encode_get_trie_nodes(non_neg_integer(), binary(), list(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  def encode_get_trie_nodes(request_id, root, paths, bytes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        root,
        paths,
        encode_integer(bytes)
      ])

    {@get_trie_nodes, payload}
  end

  @doc "Decodes a GetTrieNodes message payload."
  @spec decode_get_trie_nodes(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_trie_nodes(payload) do
    case ExRLP.decode(payload) do
      [request_id, root, paths, bytes] when is_list(paths) ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           root_hash: root,
           paths: paths,
           response_bytes: decode_integer(bytes)
         }}

      _ ->
        {:error, :invalid_get_trie_nodes}
    end
  rescue
    _ -> {:error, :invalid_get_trie_nodes}
  end

  # --- TrieNodes ---

  @doc """
  Encodes a TrieNodes message.

  Format: [request_id, nodes]
  """
  @spec encode_trie_nodes(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_trie_nodes(request_id, nodes) do
    payload =
      ExRLP.encode([
        encode_integer(request_id),
        nodes
      ])

    {@trie_nodes, payload}
  end

  @doc "Decodes a TrieNodes message payload."
  @spec decode_trie_nodes(binary()) :: {:ok, map()} | {:error, term()}
  def decode_trie_nodes(payload) do
    case ExRLP.decode(payload) do
      [request_id, nodes] when is_list(nodes) ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           nodes: nodes
         }}

      _ ->
        {:error, :invalid_trie_nodes}
    end
  rescue
    _ -> {:error, :invalid_trie_nodes}
  end

  # --- Decode dispatcher ---

  @doc "Decodes a snap/1 message by its code."
  @spec decode(non_neg_integer(), binary()) :: {:ok, {atom(), term()}} | {:error, term()}
  def decode(code, payload)

  def decode(@get_account_range, payload) do
    with {:ok, msg} <- decode_get_account_range(payload),
         do: {:ok, {:get_account_range, msg}}
  end

  def decode(@account_range, payload) do
    with {:ok, msg} <- decode_account_range(payload),
         do: {:ok, {:account_range, msg}}
  end

  def decode(@get_storage_ranges, payload) do
    with {:ok, msg} <- decode_get_storage_ranges(payload),
         do: {:ok, {:get_storage_ranges, msg}}
  end

  def decode(@storage_ranges, payload) do
    with {:ok, msg} <- decode_storage_ranges(payload),
         do: {:ok, {:storage_ranges, msg}}
  end

  def decode(@get_byte_codes, payload) do
    with {:ok, msg} <- decode_get_byte_codes(payload),
         do: {:ok, {:get_byte_codes, msg}}
  end

  def decode(@byte_codes, payload) do
    with {:ok, msg} <- decode_byte_codes(payload),
         do: {:ok, {:byte_codes, msg}}
  end

  def decode(@get_trie_nodes, payload) do
    with {:ok, msg} <- decode_get_trie_nodes(payload),
         do: {:ok, {:get_trie_nodes, msg}}
  end

  def decode(@trie_nodes, payload) do
    with {:ok, msg} <- decode_trie_nodes(payload),
         do: {:ok, {:trie_nodes, msg}}
  end

  def decode(code, _payload), do: {:error, {:unknown_snap_message, code}}

  @doc "Returns true if the message code is a snap/1 message (0x00-0x07)."
  @spec snap_message?(non_neg_integer()) :: boolean()
  def snap_message?(code) when code >= 0x00 and code <= 0x07, do: true
  def snap_message?(_code), do: false

  # --- Private helpers ---

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
  defp decode_integer(n) when is_integer(n), do: n
end
