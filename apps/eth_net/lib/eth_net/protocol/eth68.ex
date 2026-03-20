defmodule EthNet.Protocol.Eth68 do
  @moduledoc """
  eth/68 protocol messages. Implements all eth sub-protocol message types
  (msg codes 0x00-0x0a after the P2P offset of 0x10).

  Message codes (after P2P offset 0x10):
  - 0x00: Status
  - 0x01: NewBlockHashes
  - 0x02: Transactions
  - 0x03: GetBlockHeaders
  - 0x04: BlockHeaders
  - 0x05: GetBlockBodies
  - 0x06: BlockBodies
  - 0x07: NewBlock
  - 0x08: NewPooledTransactionHashes (eth/68 specific)
  - 0x09: GetPooledTransactions
  - 0x0a: PooledTransactions
  """

  # eth sub-protocol message offset (after P2P base messages)
  @eth_offset 0x10

  @status_code @eth_offset + 0x00
  @new_block_hashes_code @eth_offset + 0x01
  @transactions_code @eth_offset + 0x02
  @get_block_headers_code @eth_offset + 0x03
  @block_headers_code @eth_offset + 0x04
  @get_block_bodies_code @eth_offset + 0x05
  @block_bodies_code @eth_offset + 0x06
  @new_block_code @eth_offset + 0x07
  @new_pooled_tx_hashes_code @eth_offset + 0x08
  @get_pooled_transactions_code @eth_offset + 0x09
  @pooled_transactions_code @eth_offset + 0x0A

  @eth_version 68

  # --- Message code accessors ---

  @doc "Returns the eth/68 Status message code (with P2P offset)."
  @spec status_code() :: non_neg_integer()
  def status_code, do: @status_code

  @doc "Returns the NewBlockHashes message code."
  @spec new_block_hashes_code() :: non_neg_integer()
  def new_block_hashes_code, do: @new_block_hashes_code

  @doc "Returns the Transactions message code."
  @spec transactions_code() :: non_neg_integer()
  def transactions_code, do: @transactions_code

  @doc "Returns the GetBlockHeaders message code."
  @spec get_block_headers_code() :: non_neg_integer()
  def get_block_headers_code, do: @get_block_headers_code

  @doc "Returns the BlockHeaders message code."
  @spec block_headers_code() :: non_neg_integer()
  def block_headers_code, do: @block_headers_code

  @doc "Returns the GetBlockBodies message code."
  @spec get_block_bodies_code() :: non_neg_integer()
  def get_block_bodies_code, do: @get_block_bodies_code

  @doc "Returns the BlockBodies message code."
  @spec block_bodies_code() :: non_neg_integer()
  def block_bodies_code, do: @block_bodies_code

  @doc "Returns the NewBlock message code."
  @spec new_block_code() :: non_neg_integer()
  def new_block_code, do: @new_block_code

  @doc "Returns the NewPooledTransactionHashes message code."
  @spec new_pooled_tx_hashes_code() :: non_neg_integer()
  def new_pooled_tx_hashes_code, do: @new_pooled_tx_hashes_code

  @doc "Returns the GetPooledTransactions message code."
  @spec get_pooled_transactions_code() :: non_neg_integer()
  def get_pooled_transactions_code, do: @get_pooled_transactions_code

  @doc "Returns the PooledTransactions message code."
  @spec pooled_transactions_code() :: non_neg_integer()
  def pooled_transactions_code, do: @pooled_transactions_code

  # --- Status ---

  @doc "Encodes a Status message."
  @spec encode_status(map()) :: {non_neg_integer(), binary()}
  def encode_status(params) do
    %{
      network_id: network_id,
      total_difficulty: td,
      best_hash: best_hash,
      genesis_hash: genesis_hash,
      fork_id: fork_id
    } = params

    payload =
      ExRLP.encode([
        @eth_version,
        encode_integer(network_id),
        encode_integer(td),
        best_hash,
        genesis_hash,
        EthNet.ForkID.encode(fork_id)
      ])

    {@status_code, payload}
  end

  @doc "Decodes a Status message payload."
  @spec decode_status(binary()) :: {:ok, map()} | {:error, term()}
  def decode_status(payload) do
    case ExRLP.decode(payload) do
      [version, network_id, td, best_hash, genesis_hash, fork_id_rlp | _] ->
        {:ok,
         %{
           version: decode_integer(version),
           network_id: decode_integer(network_id),
           total_difficulty: decode_integer(td),
           best_hash: best_hash,
           genesis_hash: genesis_hash,
           fork_id: EthNet.ForkID.decode(fork_id_rlp)
         }}

      _ ->
        {:error, :invalid_status_message}
    end
  end

  @doc "Builds a Status message for mainnet with the given head info."
  @spec build_mainnet_status(non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  def build_mainnet_status(head_block \\ 0, head_timestamp \\ 0) do
    genesis_hash = EthNet.Chain.genesis_hash(:mainnet)
    fork_id = EthNet.ForkID.compute(:mainnet, head_block, head_timestamp)

    encode_status(%{
      network_id: EthNet.Chain.network_id(:mainnet),
      total_difficulty: EthNet.Chain.terminal_td(:mainnet),
      best_hash: genesis_hash,
      genesis_hash: genesis_hash,
      fork_id: fork_id
    })
  end

  # --- NewBlockHashes ---

  @doc "Encodes a NewBlockHashes message: [[hash, number], ...]."
  @spec encode_new_block_hashes([{binary(), non_neg_integer()}]) ::
          {non_neg_integer(), binary()}
  def encode_new_block_hashes(hash_number_pairs) do
    items =
      Enum.map(hash_number_pairs, fn {hash, number} ->
        [hash, encode_integer(number)]
      end)

    {@new_block_hashes_code, ExRLP.encode(items)}
  end

  @doc "Decodes a NewBlockHashes message payload."
  @spec decode_new_block_hashes(binary()) ::
          {:ok, [{binary(), non_neg_integer()}]} | {:error, term()}
  def decode_new_block_hashes(payload) do
    case ExRLP.decode(payload) do
      items when is_list(items) ->
        pairs =
          Enum.map(items, fn [hash, number] ->
            {hash, decode_integer(number)}
          end)

        {:ok, pairs}

      _ ->
        {:error, :invalid_new_block_hashes}
    end
  rescue
    _ -> {:error, :invalid_new_block_hashes}
  end

  # --- Transactions ---

  @doc "Encodes a Transactions message."
  @spec encode_transactions([binary()]) :: {non_neg_integer(), binary()}
  def encode_transactions(transactions) do
    {@transactions_code, ExRLP.encode(transactions)}
  end

  @doc "Decodes a Transactions message payload."
  @spec decode_transactions(binary()) :: {:ok, [binary()]} | {:error, term()}
  def decode_transactions(payload) do
    {:ok, ExRLP.decode(payload)}
  rescue
    _ -> {:error, :invalid_transactions}
  end

  # --- GetBlockHeaders ---

  @doc "Encodes a GetBlockHeaders request: [request_id, [origin, amount, skip, reverse]]."
  @spec encode_get_block_headers(
          non_neg_integer(),
          binary() | non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          boolean()
        ) :: {non_neg_integer(), binary()}
  def encode_get_block_headers(request_id, origin, amount, skip, reverse) do
    origin_encoded = encode_origin(origin)
    reverse_val = if reverse, do: 1, else: 0

    payload =
      ExRLP.encode([
        encode_integer(request_id),
        [
          origin_encoded,
          encode_integer(amount),
          encode_integer(skip),
          encode_integer(reverse_val)
        ]
      ])

    {@get_block_headers_code, payload}
  end

  @doc "Decodes a GetBlockHeaders request payload."
  @spec decode_get_block_headers(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_block_headers(payload) do
    case ExRLP.decode(payload) do
      [request_id, [origin, amount, skip, reverse]] ->
        {:ok,
         %{
           request_id: decode_integer(request_id),
           origin: decode_origin(origin),
           amount: decode_integer(amount),
           skip: decode_integer(skip),
           reverse: decode_integer(reverse) != 0
         }}

      _ ->
        {:error, :invalid_get_block_headers}
    end
  rescue
    _ -> {:error, :invalid_get_block_headers}
  end

  # --- BlockHeaders ---

  @doc "Encodes a BlockHeaders response: [request_id, [header1_rlp, ...]]."
  @spec encode_block_headers(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_block_headers(request_id, headers) do
    payload = ExRLP.encode([encode_integer(request_id), headers])
    {@block_headers_code, payload}
  end

  @doc "Decodes a BlockHeaders response payload."
  @spec decode_block_headers(binary()) :: {:ok, map()} | {:error, term()}
  def decode_block_headers(payload) do
    case ExRLP.decode(payload) do
      [request_id, headers] when is_list(headers) ->
        {:ok, %{request_id: decode_integer(request_id), headers: headers}}

      _ ->
        {:error, :invalid_block_headers}
    end
  rescue
    _ -> {:error, :invalid_block_headers}
  end

  # --- GetBlockBodies ---

  @doc "Encodes a GetBlockBodies request: [request_id, [hash1, hash2, ...]]."
  @spec encode_get_block_bodies(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_get_block_bodies(request_id, hashes) do
    payload = ExRLP.encode([encode_integer(request_id), hashes])
    {@get_block_bodies_code, payload}
  end

  @doc "Decodes a GetBlockBodies request payload."
  @spec decode_get_block_bodies(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_block_bodies(payload) do
    case ExRLP.decode(payload) do
      [request_id, hashes] when is_list(hashes) ->
        {:ok, %{request_id: decode_integer(request_id), hashes: hashes}}

      _ ->
        {:error, :invalid_get_block_bodies}
    end
  rescue
    _ -> {:error, :invalid_get_block_bodies}
  end

  # --- BlockBodies ---

  @doc "Encodes a BlockBodies response: [request_id, [body1, body2, ...]]."
  @spec encode_block_bodies(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_block_bodies(request_id, bodies) do
    payload = ExRLP.encode([encode_integer(request_id), bodies])
    {@block_bodies_code, payload}
  end

  @doc "Decodes a BlockBodies response payload."
  @spec decode_block_bodies(binary()) :: {:ok, map()} | {:error, term()}
  def decode_block_bodies(payload) do
    case ExRLP.decode(payload) do
      [request_id, bodies] when is_list(bodies) ->
        {:ok, %{request_id: decode_integer(request_id), bodies: bodies}}

      _ ->
        {:error, :invalid_block_bodies}
    end
  rescue
    _ -> {:error, :invalid_block_bodies}
  end

  # --- NewBlock ---

  @doc "Encodes a NewBlock message."
  @spec encode_new_block(binary(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  def encode_new_block(block_rlp, td) do
    payload = ExRLP.encode([block_rlp, encode_integer(td)])
    {@new_block_code, payload}
  end

  @doc "Decodes a NewBlock message payload."
  @spec decode_new_block(binary()) :: {:ok, map()} | {:error, term()}
  def decode_new_block(payload) do
    case ExRLP.decode(payload) do
      [block, td] ->
        {:ok, %{block: block, total_difficulty: decode_integer(td)}}

      _ ->
        {:error, :invalid_new_block}
    end
  rescue
    _ -> {:error, :invalid_new_block}
  end

  # --- NewPooledTransactionHashes (eth/68 specific) ---

  @doc """
  Encodes NewPooledTransactionHashes (eth/68): [[types], [sizes], [hashes]].

  Each entry is a tuple of {type, size, hash}.
  """
  @spec encode_new_pooled_tx_hashes([{non_neg_integer(), non_neg_integer(), binary()}]) ::
          {non_neg_integer(), binary()}
  def encode_new_pooled_tx_hashes(entries) do
    {types, sizes, hashes} =
      Enum.reduce(entries, {[], [], []}, fn {type, size, hash}, {ts, ss, hs} ->
        {[encode_integer(type) | ts], [encode_integer(size) | ss], [hash | hs]}
      end)

    payload =
      ExRLP.encode([
        Enum.reverse(types),
        Enum.reverse(sizes),
        Enum.reverse(hashes)
      ])

    {@new_pooled_tx_hashes_code, payload}
  end

  @doc "Decodes a NewPooledTransactionHashes (eth/68) message payload."
  @spec decode_new_pooled_tx_hashes(binary()) :: {:ok, list()} | {:error, term()}
  def decode_new_pooled_tx_hashes(payload) do
    case ExRLP.decode(payload) do
      [types, sizes, hashes] when is_list(types) and is_list(sizes) and is_list(hashes) ->
        entries =
          [types, sizes, hashes]
          |> Enum.zip()
          |> Enum.map(fn {type, size, hash} ->
            {decode_integer(type), decode_integer(size), hash}
          end)

        {:ok, entries}

      _ ->
        {:error, :invalid_new_pooled_tx_hashes}
    end
  rescue
    _ -> {:error, :invalid_new_pooled_tx_hashes}
  end

  # --- GetPooledTransactions ---

  @doc "Encodes a GetPooledTransactions request: [request_id, [hash1, ...]]."
  @spec encode_get_pooled_transactions(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_get_pooled_transactions(request_id, hashes) do
    payload = ExRLP.encode([encode_integer(request_id), hashes])
    {@get_pooled_transactions_code, payload}
  end

  @doc "Decodes a GetPooledTransactions request payload."
  @spec decode_get_pooled_transactions(binary()) :: {:ok, map()} | {:error, term()}
  def decode_get_pooled_transactions(payload) do
    case ExRLP.decode(payload) do
      [request_id, hashes] when is_list(hashes) ->
        {:ok, %{request_id: decode_integer(request_id), hashes: hashes}}

      _ ->
        {:error, :invalid_get_pooled_transactions}
    end
  rescue
    _ -> {:error, :invalid_get_pooled_transactions}
  end

  # --- PooledTransactions ---

  @doc "Encodes a PooledTransactions response: [request_id, [tx1, ...]]."
  @spec encode_pooled_transactions(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  def encode_pooled_transactions(request_id, transactions) do
    payload = ExRLP.encode([encode_integer(request_id), transactions])
    {@pooled_transactions_code, payload}
  end

  @doc "Decodes a PooledTransactions response payload."
  @spec decode_pooled_transactions(binary()) :: {:ok, map()} | {:error, term()}
  def decode_pooled_transactions(payload) do
    case ExRLP.decode(payload) do
      [request_id, transactions] when is_list(transactions) ->
        {:ok, %{request_id: decode_integer(request_id), transactions: transactions}}

      _ ->
        {:error, :invalid_pooled_transactions}
    end
  rescue
    _ -> {:error, :invalid_pooled_transactions}
  end

  # --- Decode dispatcher ---

  @doc "Decodes an eth/68 message by its code."
  @spec decode(non_neg_integer(), binary()) :: {:ok, {atom(), term()}} | {:error, term()}
  def decode(code, payload)

  def decode(@status_code, payload) do
    with {:ok, msg} <- decode_status(payload), do: {:ok, {:status, msg}}
  end

  def decode(@new_block_hashes_code, payload) do
    with {:ok, msg} <- decode_new_block_hashes(payload), do: {:ok, {:new_block_hashes, msg}}
  end

  def decode(@transactions_code, payload) do
    with {:ok, msg} <- decode_transactions(payload), do: {:ok, {:transactions, msg}}
  end

  def decode(@get_block_headers_code, payload) do
    with {:ok, msg} <- decode_get_block_headers(payload),
         do: {:ok, {:get_block_headers, msg}}
  end

  def decode(@block_headers_code, payload) do
    with {:ok, msg} <- decode_block_headers(payload), do: {:ok, {:block_headers, msg}}
  end

  def decode(@get_block_bodies_code, payload) do
    with {:ok, msg} <- decode_get_block_bodies(payload),
         do: {:ok, {:get_block_bodies, msg}}
  end

  def decode(@block_bodies_code, payload) do
    with {:ok, msg} <- decode_block_bodies(payload), do: {:ok, {:block_bodies, msg}}
  end

  def decode(@new_block_code, payload) do
    with {:ok, msg} <- decode_new_block(payload), do: {:ok, {:new_block, msg}}
  end

  def decode(@new_pooled_tx_hashes_code, payload) do
    with {:ok, msg} <- decode_new_pooled_tx_hashes(payload),
         do: {:ok, {:new_pooled_tx_hashes, msg}}
  end

  def decode(@get_pooled_transactions_code, payload) do
    with {:ok, msg} <- decode_get_pooled_transactions(payload),
         do: {:ok, {:get_pooled_transactions, msg}}
  end

  def decode(@pooled_transactions_code, payload) do
    with {:ok, msg} <- decode_pooled_transactions(payload),
         do: {:ok, {:pooled_transactions, msg}}
  end

  def decode(code, _payload), do: {:error, {:unknown_eth_message, code}}

  @doc "Returns true if the message code is an eth/68 message."
  @spec eth_message?(non_neg_integer()) :: boolean()
  def eth_message?(code), do: code >= @eth_offset

  # --- Private helpers ---

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
  defp decode_integer(n) when is_integer(n), do: n

  defp encode_origin(hash) when is_binary(hash) and byte_size(hash) == 32, do: hash
  defp encode_origin(number) when is_integer(number), do: encode_integer(number)

  defp decode_origin(bin) when is_binary(bin) and byte_size(bin) == 32, do: {:hash, bin}
  defp decode_origin(bin) when is_binary(bin), do: {:number, decode_integer(bin)}
  defp decode_origin(n) when is_integer(n), do: {:number, n}
end
