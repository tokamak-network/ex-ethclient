defmodule EthNet.Protocol.Eth70 do
  @moduledoc """
  eth/70 wire protocol - adds execution requests support.

  eth/70 builds on eth/69 with:
  - Status version bumped to 70
  - Same simplified status format as eth/69 (no totalDifficulty)
  - All other messages identical to eth/68/69

  Status format: [version, network_id, genesis_hash, fork_id, best_hash]
  """

  alias EthNet.Protocol.Eth68

  # eth sub-protocol message offset (after P2P base messages)
  @eth_offset 0x10

  @status_code @eth_offset + 0x00

  @eth_version 70

  # --- Message code accessors ---

  @doc "Returns the eth/70 Status message code (with P2P offset)."
  @spec status_code() :: non_neg_integer()
  def status_code, do: @status_code

  @doc "Returns the NewBlockHashes message code."
  @spec new_block_hashes_code() :: non_neg_integer()
  defdelegate new_block_hashes_code(), to: Eth68

  @doc "Returns the Transactions message code."
  @spec transactions_code() :: non_neg_integer()
  defdelegate transactions_code(), to: Eth68

  @doc "Returns the GetBlockHeaders message code."
  @spec get_block_headers_code() :: non_neg_integer()
  defdelegate get_block_headers_code(), to: Eth68

  @doc "Returns the BlockHeaders message code."
  @spec block_headers_code() :: non_neg_integer()
  defdelegate block_headers_code(), to: Eth68

  @doc "Returns the GetBlockBodies message code."
  @spec get_block_bodies_code() :: non_neg_integer()
  defdelegate get_block_bodies_code(), to: Eth68

  @doc "Returns the BlockBodies message code."
  @spec block_bodies_code() :: non_neg_integer()
  defdelegate block_bodies_code(), to: Eth68

  @doc "Returns the NewBlock message code."
  @spec new_block_code() :: non_neg_integer()
  defdelegate new_block_code(), to: Eth68

  @doc "Returns the NewPooledTransactionHashes message code."
  @spec new_pooled_tx_hashes_code() :: non_neg_integer()
  defdelegate new_pooled_tx_hashes_code(), to: Eth68

  @doc "Returns the GetPooledTransactions message code."
  @spec get_pooled_transactions_code() :: non_neg_integer()
  defdelegate get_pooled_transactions_code(), to: Eth68

  @doc "Returns the PooledTransactions message code."
  @spec pooled_transactions_code() :: non_neg_integer()
  defdelegate pooled_transactions_code(), to: Eth68

  # --- Status (eth/70 specific — same as eth/69 but version 70) ---

  @doc """
  Encodes a Status message for eth/70.

  Format: [version, network_id, genesis_hash, fork_id, best_hash]
  Same as eth/69 but version field is 70.
  """
  @spec encode_status(map()) :: {non_neg_integer(), binary()}
  def encode_status(params) do
    %{
      network_id: network_id,
      genesis_hash: genesis_hash,
      fork_id: fork_id,
      best_hash: best_hash
    } = params

    payload =
      ExRLP.encode([
        @eth_version,
        encode_integer(network_id),
        genesis_hash,
        EthNet.ForkID.encode(fork_id),
        best_hash
      ])

    {@status_code, payload}
  end

  @doc "Decodes a Status message payload for eth/70."
  @spec decode_status(binary()) :: {:ok, map()} | {:error, term()}
  def decode_status(payload) do
    case ExRLP.decode(payload) do
      [version, network_id, genesis_hash, fork_id_rlp, best_hash | _] ->
        {:ok,
         %{
           version: decode_integer(version),
           network_id: decode_integer(network_id),
           genesis_hash: genesis_hash,
           fork_id: EthNet.ForkID.decode(fork_id_rlp),
           best_hash: best_hash
         }}

      _ ->
        {:error, :invalid_status_message}
    end
  end

  # --- Delegated messages (identical to eth/68/69) ---

  @doc "Encodes a NewBlockHashes message."
  @spec encode_new_block_hashes([{binary(), non_neg_integer()}]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_new_block_hashes(hash_number_pairs), to: Eth68

  @doc "Decodes a NewBlockHashes message payload."
  @spec decode_new_block_hashes(binary()) ::
          {:ok, [{binary(), non_neg_integer()}]} | {:error, term()}
  defdelegate decode_new_block_hashes(data), to: Eth68

  @doc "Encodes a Transactions message."
  @spec encode_transactions([binary()]) :: {non_neg_integer(), binary()}
  defdelegate encode_transactions(transactions), to: Eth68

  @doc "Decodes a Transactions message payload."
  @spec decode_transactions(binary()) :: {:ok, [binary()]} | {:error, term()}
  defdelegate decode_transactions(data), to: Eth68

  @doc "Encodes a GetBlockHeaders request."
  @spec encode_get_block_headers(
          non_neg_integer(),
          binary() | non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          boolean()
        ) :: {non_neg_integer(), binary()}
  defdelegate encode_get_block_headers(request_id, origin, amount, skip, reverse), to: Eth68

  @doc "Decodes a GetBlockHeaders request payload."
  @spec decode_get_block_headers(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_get_block_headers(data), to: Eth68

  @doc "Encodes a BlockHeaders response."
  @spec encode_block_headers(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_block_headers(request_id, headers), to: Eth68

  @doc "Decodes a BlockHeaders response payload."
  @spec decode_block_headers(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_block_headers(data), to: Eth68

  @doc "Encodes a GetBlockBodies request."
  @spec encode_get_block_bodies(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_get_block_bodies(request_id, hashes), to: Eth68

  @doc "Decodes a GetBlockBodies request payload."
  @spec decode_get_block_bodies(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_get_block_bodies(data), to: Eth68

  @doc "Encodes a BlockBodies response."
  @spec encode_block_bodies(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_block_bodies(request_id, bodies), to: Eth68

  @doc "Decodes a BlockBodies response payload."
  @spec decode_block_bodies(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_block_bodies(data), to: Eth68

  @doc "Encodes a NewBlock message."
  @spec encode_new_block(binary(), non_neg_integer()) ::
          {non_neg_integer(), binary()}
  defdelegate encode_new_block(block_rlp, td), to: Eth68

  @doc "Decodes a NewBlock message payload."
  @spec decode_new_block(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_new_block(data), to: Eth68

  @doc "Encodes NewPooledTransactionHashes (eth/68 format)."
  @spec encode_new_pooled_tx_hashes([{non_neg_integer(), non_neg_integer(), binary()}]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_new_pooled_tx_hashes(entries), to: Eth68

  @doc "Decodes a NewPooledTransactionHashes message payload."
  @spec decode_new_pooled_tx_hashes(binary()) :: {:ok, list()} | {:error, term()}
  defdelegate decode_new_pooled_tx_hashes(data), to: Eth68

  @doc "Encodes a GetPooledTransactions request."
  @spec encode_get_pooled_transactions(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_get_pooled_transactions(request_id, hashes), to: Eth68

  @doc "Decodes a GetPooledTransactions request payload."
  @spec decode_get_pooled_transactions(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_get_pooled_transactions(data), to: Eth68

  @doc "Encodes a PooledTransactions response."
  @spec encode_pooled_transactions(non_neg_integer(), [binary()]) ::
          {non_neg_integer(), binary()}
  defdelegate encode_pooled_transactions(request_id, transactions), to: Eth68

  @doc "Decodes a PooledTransactions response payload."
  @spec decode_pooled_transactions(binary()) :: {:ok, map()} | {:error, term()}
  defdelegate decode_pooled_transactions(data), to: Eth68

  @doc "Returns true if the message code is an eth message."
  @spec eth_message?(non_neg_integer()) :: boolean()
  defdelegate eth_message?(code), to: Eth68

  # --- Private helpers ---

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
  defp decode_integer(n) when is_integer(n), do: n
end
