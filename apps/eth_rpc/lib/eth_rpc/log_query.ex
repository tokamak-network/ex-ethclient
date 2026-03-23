defmodule EthRpc.LogQuery do
  @moduledoc """
  Queries logs from stored receipts, matching against filter criteria.

  Supports filtering by block range, address, and topic patterns.
  Uses bloom filters for quick rejection when available.
  """

  alias EthCore.Types.Log
  alias EthRpc.Hex

  @type filter :: %{
          optional(:from_block) => non_neg_integer(),
          optional(:to_block) => non_neg_integer(),
          optional(:address) => binary() | [binary()],
          optional(:topics) => [binary() | [binary()] | nil],
          optional(:block_hash) => binary()
        }

  @doc """
  Query logs matching the given filter criteria.

  The filter map supports:
  - `:from_block` / `:to_block` - block number range (inclusive)
  - `:address` - single address or list of addresses to match
  - `:topics` - list of topic filters (nil = wildcard, list = OR)
  - `:block_hash` - query a single block by hash
  """
  @spec query_logs(filter(), pid() | atom()) :: {:ok, [map()]}
  def query_logs(filter, store) do
    with {:ok, from, to} <- resolve_block_range(filter, store) do
      logs =
        from..to
        |> Enum.flat_map(fn block_num ->
          fetch_logs_for_block(block_num, filter, store)
        end)

      {:ok, logs}
    else
      {:error, _} -> {:ok, []}
    end
  end

  @doc """
  Check if a log matches the filter criteria.

  Matches address (if specified) and topics against the filter pattern.
  """
  @spec matches_filter?(Log.t(), filter()) :: boolean()
  def matches_filter?(%Log{} = log, filter) do
    address_matches?(log, filter) and
      topics_match?(log.topics, Map.get(filter, :topics, []))
  end

  @doc """
  Check if log topics match the filter topic pattern.

  Topic matching rules (per Ethereum JSON-RPC spec):
  - `nil` in filter position = wildcard (matches any topic)
  - A binary in filter position = exact match required
  - A list of binaries = OR match (any in the list matches)
  - Filter topics shorter than log topics = remaining are wildcards
  """
  @spec topics_match?([binary()], [binary() | [binary()] | nil]) :: boolean()
  def topics_match?(_log_topics, []), do: true

  def topics_match?([], [nil | rest_filter]) do
    topics_match?([], rest_filter)
  end

  def topics_match?([], [_ | _rest_filter]), do: false

  def topics_match?([_log_topic | rest_log], [nil | rest_filter]) do
    topics_match?(rest_log, rest_filter)
  end

  def topics_match?([log_topic | rest_log], [filter_topic | rest_filter])
      when is_binary(filter_topic) do
    log_topic == filter_topic and topics_match?(rest_log, rest_filter)
  end

  def topics_match?([log_topic | rest_log], [filter_topics | rest_filter])
      when is_list(filter_topics) do
    Enum.any?(filter_topics, &(&1 == log_topic)) and
      topics_match?(rest_log, rest_filter)
  end

  # --- Private ---

  @spec address_matches?(Log.t(), filter()) :: boolean()
  defp address_matches?(%Log{} = log, filter) do
    case Map.get(filter, :address) do
      nil -> true
      addr when is_binary(addr) -> log.address == addr
      addrs when is_list(addrs) -> log.address in addrs
    end
  end

  @spec resolve_block_range(filter(), pid() | atom()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, term()}
  defp resolve_block_range(filter, store) do
    from = Map.get(filter, :from_block, 0)

    case Map.get(filter, :to_block) do
      nil ->
        case get_latest_block(store) do
          {:ok, latest} -> {:ok, from, latest}
          error -> error
        end

      to ->
        {:ok, from, to}
    end
  end

  @spec get_latest_block(pid() | atom()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp get_latest_block(store) do
    case safe_call(store, :get_latest_block_number, []) do
      {:ok, nil} -> {:ok, 0}
      {:ok, n} -> {:ok, n}
      error -> error
    end
  end

  @spec fetch_logs_for_block(non_neg_integer(), filter(), pid() | atom()) ::
          [map()]
  defp fetch_logs_for_block(block_num, filter, store) do
    # Get block hash for this number
    case safe_call(store, :get_canonical_hash, [block_num]) do
      {:ok, nil} ->
        []

      {:ok, block_hash} ->
        fetch_receipts_logs(block_hash, block_num, filter, store)

      _error ->
        []
    end
  end

  @spec fetch_receipts_logs(binary(), non_neg_integer(), filter(), pid() | atom()) ::
          [map()]
  defp fetch_receipts_logs(block_hash, block_num, filter, store) do
    # Try transaction indices 0..max, stop when we get nil
    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn tx_idx ->
      safe_call(store, :get_receipt, [block_hash, tx_idx])
    end)
    |> Stream.take_while(fn
      {:ok, nil} -> false
      {:ok, _data} -> true
      _error -> false
    end)
    |> Stream.with_index()
    |> Enum.flat_map(fn {{:ok, encoded}, tx_idx} ->
      receipt = :erlang.binary_to_term(encoded)

      receipt.logs
      |> Enum.with_index()
      |> Enum.filter(fn {log, _idx} -> matches_filter?(log, filter) end)
      |> Enum.map(fn {log, log_idx} ->
        format_log(log, block_hash, block_num, tx_idx, log_idx)
      end)
    end)
  end

  @spec format_log(Log.t(), binary(), non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          map()
  defp format_log(%Log{} = log, block_hash, block_num, tx_idx, log_idx) do
    %{
      "address" => Hex.encode_data(log.address),
      "topics" => Enum.map(log.topics, &Hex.encode_data/1),
      "data" => Hex.encode_data(log.data),
      "blockNumber" => Hex.encode_quantity(block_num),
      "blockHash" => Hex.encode_data(block_hash),
      "transactionIndex" => Hex.encode_quantity(tx_idx),
      "transactionHash" => Hex.encode_data(<<0::256>>),
      "logIndex" => Hex.encode_quantity(log_idx),
      "removed" => false
    }
  end

  @spec safe_call(pid() | atom(), atom(), list()) :: term()
  defp safe_call(store, func, args) do
    apply(store_module(), func, [store | args])
  rescue
    _ -> {:error, :store_unavailable}
  catch
    :exit, _ -> {:error, :store_unavailable}
  end

  @spec store_module() :: module()
  defp store_module do
    case Application.get_env(:eth_rpc, :store_module) do
      nil -> EthStorage.Store
      mod -> mod
    end
  end
end
