defmodule EthStorage.Backend.Memory do
  @moduledoc """
  ETS-based in-memory storage backend.

  Creates one ETS table per logical table for fast concurrent reads.
  Suitable for testing and development environments.
  """

  @behaviour EthStorage.Backend

  @tables [
    :block_numbers,
    :canonical_hashes,
    :headers,
    :bodies,
    :receipts,
    :tx_locations,
    :account_trie_nodes,
    :storage_trie_nodes,
    :account_codes,
    :chain_config,
    :blobs
  ]

  @doc "Returns the list of logical table names."
  @spec tables() :: [atom()]
  def tables, do: @tables

  @impl true
  @spec init(keyword()) :: {:ok, %{atom() => :ets.table()}} | {:error, term()}
  def init(_opts \\ []) do
    ets_tables =
      Map.new(@tables, fn name ->
        tid = :ets.new(name, [:set, :public, read_concurrency: true])
        {name, tid}
      end)

    {:ok, ets_tables}
  end

  @impl true
  @spec get(map(), atom(), binary()) :: {:ok, binary() | nil} | {:error, term()}
  def get(state, table, key) do
    with {:ok, tid} <- lookup_table(state, table) do
      case :ets.lookup(tid, key) do
        [{^key, value}] -> {:ok, value}
        [] -> {:ok, nil}
      end
    end
  end

  @impl true
  @spec put(map(), atom(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def put(state, table, key, value) do
    with {:ok, tid} <- lookup_table(state, table) do
      :ets.insert(tid, {key, value})
      {:ok, state}
    end
  end

  @impl true
  @spec delete(map(), atom(), binary()) :: {:ok, map()} | {:error, term()}
  def delete(state, table, key) do
    with {:ok, tid} <- lookup_table(state, table) do
      :ets.delete(tid, key)
      {:ok, state}
    end
  end

  @impl true
  @spec batch_put(map(), [{atom(), binary(), binary()}]) ::
          {:ok, map()} | {:error, term()}
  def batch_put(state, entries) do
    result =
      Enum.reduce_while(entries, :ok, fn {table, key, value}, :ok ->
        case put(state, table, key, value) do
          {:ok, _} -> {:cont, :ok}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      :ok -> {:ok, state}
      {:error, _} = err -> err
    end
  end

  @impl true
  @spec count(map(), atom()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(state, table) do
    with {:ok, tid} <- lookup_table(state, table) do
      {:ok, :ets.info(tid, :size)}
    end
  end

  @spec lookup_table(map(), atom()) :: {:ok, :ets.table()} | {:error, :unknown_table}
  defp lookup_table(state, table) do
    case Map.fetch(state, table) do
      {:ok, tid} -> {:ok, tid}
      :error -> {:error, :unknown_table}
    end
  end
end
