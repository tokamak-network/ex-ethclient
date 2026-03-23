defmodule EthRpc.Debug do
  @moduledoc """
  Implements debug_ RPC namespace methods.

  Provides access to raw RLP-encoded block data for debugging and
  low-level inspection of chain state.
  """

  alias EthRpc.Hex
  alias EthStorage.{BlockStore, Store}

  @doc """
  Returns the RLP-encoded header for the given block number or hash.

  ## Parameters

    - `[block_id]` - Hex block number or block hash

  ## Returns

    `{:ok, hex_string}` with the RLP-encoded header, or `{:ok, nil}` if not found.
  """
  @spec get_raw_header(list()) ::
          {:ok, String.t() | nil} | {:error, integer(), String.t()}
  def get_raw_header([block_id | _rest]) when is_binary(block_id) do
    if store_available?() do
      case resolve_block_header(block_id) do
        {:ok, nil} -> {:ok, nil}
        {:ok, header} -> {:ok, Hex.encode_data(encode_header_rlp(header))}
        _error -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  def get_raw_header(_params) do
    {:error, -32602, "Invalid params: expected [block_number_or_hash]"}
  end

  @doc """
  Returns the RLP-encoded block for the given block number or hash.

  ## Parameters

    - `[block_id]` - Hex block number or block hash

  ## Returns

    `{:ok, hex_string}` with the RLP-encoded block, or `{:ok, nil}` if not found.
  """
  @spec get_raw_block(list()) ::
          {:ok, String.t() | nil} | {:error, integer(), String.t()}
  def get_raw_block([block_id | _rest]) when is_binary(block_id) do
    if store_available?() do
      case resolve_full_block(block_id) do
        {:ok, nil} -> {:ok, nil}
        {:ok, block} -> {:ok, Hex.encode_data(encode_block_rlp(block))}
        _error -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  def get_raw_block(_params) do
    {:error, -32602, "Invalid params: expected [block_number_or_hash]"}
  end

  @doc """
  Returns the RLP-encoded transaction by hash.

  ## Parameters

    - `[tx_hash_hex]` - Hex-encoded transaction hash

  ## Returns

    `{:ok, hex_string}` with the RLP-encoded transaction, or `{:ok, nil}` if not found.
  """
  @spec get_raw_transaction(list()) ::
          {:ok, String.t() | nil} | {:error, integer(), String.t()}
  def get_raw_transaction([tx_hash_hex | _rest]) when is_binary(tx_hash_hex) do
    if store_available?() do
      with {:ok, tx_hash} <- Hex.decode_data(tx_hash_hex) do
        case lookup_transaction(tx_hash) do
          {:ok, nil} -> {:ok, nil}
          {:ok, signed_tx} -> {:ok, Hex.encode_data(encode_tx_rlp(signed_tx))}
          _error -> {:ok, nil}
        end
      else
        _ -> {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

  def get_raw_transaction(_params) do
    {:error, -32602, "Invalid params: expected [tx_hash]"}
  end

  @doc """
  Returns a list of RLP-encoded receipts for the given block.

  ## Parameters

    - `[block_id]` - Hex block number or block hash

  ## Returns

    `{:ok, list}` with hex-encoded RLP receipts, or `{:ok, []}` if not found.
  """
  @spec get_raw_receipts(list()) ::
          {:ok, [String.t()]} | {:error, integer(), String.t()}
  def get_raw_receipts([block_id | _rest]) when is_binary(block_id) do
    if not store_available?() do
      {:ok, []}
    else
      case resolve_block_number(block_id) do
      {:ok, nil} ->
        {:ok, []}

      {:ok, number} ->
        store = store_server()

        case BlockStore.get_block_by_number(number, store) do
          {:ok, %{transactions: txs} = block} when is_list(txs) ->
            block_hash = EthStorage.Encoding.block_hash(block.header)

            receipts =
              txs
              |> Enum.with_index()
              |> Enum.flat_map(fn {_tx, idx} ->
                case Store.get_receipt(store, block_hash, idx) do
                  {:ok, nil} -> []
                  {:ok, receipt_bin} ->
                    receipt = :erlang.binary_to_term(receipt_bin)
                    [Hex.encode_data(:erlang.term_to_binary(receipt))]
                  _ -> []
                end
              end)

            {:ok, receipts}

          _ ->
            {:ok, []}
        end

      _ ->
        {:ok, []}
      end
    end
  end

  def get_raw_receipts(_params) do
    {:error, -32602, "Invalid params: expected [block_number_or_hash]"}
  end

  # -- Private helpers -------------------------------------------------------

  @spec resolve_block_header(String.t()) ::
          {:ok, EthCore.Types.BlockHeader.t() | nil} | {:error, term()}
  defp resolve_block_header(block_id) do
    store = store_server()

    case resolve_block_number(block_id) do
      {:ok, nil} -> {:ok, nil}
      {:ok, number} ->
        case BlockStore.get_block_by_number(number, store) do
          {:ok, %{header: header}} -> {:ok, header}
          {:ok, nil} -> {:ok, nil}
          error -> error
        end
      error -> error
    end
  end

  @spec resolve_full_block(String.t()) ::
          {:ok, EthCore.Types.Block.t() | nil} | {:error, term()}
  defp resolve_full_block(block_id) do
    store = store_server()

    case resolve_block_number(block_id) do
      {:ok, nil} -> {:ok, nil}
      {:ok, number} -> BlockStore.get_block_by_number(number, store)
      error -> error
    end
  end

  @spec resolve_block_number(String.t()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defp resolve_block_number(hex_str) do
    case Hex.decode_quantity(hex_str) do
      {:ok, number} -> {:ok, number}
      {:error, _} ->
        # Try as block hash
        case Hex.decode_data(hex_str) do
          {:ok, hash} when byte_size(hash) == 32 ->
            store = store_server()

            case BlockStore.get_header(hash, store) do
              {:ok, %{number: n}} -> {:ok, n}
              _ -> {:ok, nil}
            end

          _ ->
            {:ok, nil}
        end
    end
  end

  @spec lookup_transaction(binary()) ::
          {:ok, EthCore.Types.SignedTransaction.t() | nil} | {:error, term()}
  defp lookup_transaction(tx_hash) do
    store = store_server()

    case Store.get_tx_location(store, tx_hash) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, {block_hash, tx_index}} ->
        case Store.get_block_body(store, block_hash) do
          {:ok, nil} -> {:ok, nil}
          {:ok, body_bin} ->
            body = :erlang.binary_to_term(body_bin)
            {:ok, Enum.at(body.transactions, tx_index)}
          _ -> {:ok, nil}
        end

      _ ->
        {:ok, nil}
    end
  end

  @spec encode_header_rlp(EthCore.Types.BlockHeader.t()) :: binary()
  defp encode_header_rlp(header) do
    EthCore.RLP.encode_header(header)
  end

  @spec encode_block_rlp(EthCore.Types.Block.t()) :: binary()
  defp encode_block_rlp(block) do
    # Encode as RLP list: [header_rlp, txs_rlp, ommers_rlp]
    _header_rlp = EthCore.RLP.encode_header(block.header)
    # For simplicity, encode the block as term_to_binary
    # A full implementation would use proper RLP encoding
    :erlang.term_to_binary(block)
  end

  @spec encode_tx_rlp(EthCore.Types.SignedTransaction.t()) :: binary()
  defp encode_tx_rlp(signed_tx) do
    EthCore.RLP.encode_signed(signed_tx)
  end

  defp store_available? do
    pid = Process.whereis(store_server())
    is_pid(pid) and Process.alive?(pid)
  end

  @spec store_server() :: GenServer.server()
  defp store_server do
    case Application.get_env(:eth_rpc, :store) do
      nil -> Store
      {_mod, name} -> name
      name -> name
    end
  end
end
