defmodule EthStorage.Backend.RocksDB do
  @moduledoc """
  RocksDB-based persistent storage backend.

  Uses Rust NIFs via `EthStorage.RocksNative` to provide high-performance
  persistent storage. Each logical table maps to a RocksDB column family.
  """

  @behaviour EthStorage.Backend

  @tables [
    :block_numbers,
    :canonical_hashes,
    :headers,
    :bodies,
    :receipts,
    :account_trie_nodes,
    :storage_trie_nodes,
    :account_codes,
    :chain_config
  ]

  @doc "Returns the list of logical table names."
  @spec tables() :: [atom()]
  def tables, do: @tables

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:error, term()}
  def init(opts) do
    dir = Keyword.get(opts, :datadir, "./data/rocksdb")
    cf_names = Enum.map(@tables, &Atom.to_string/1)

    with :ok <- ensure_dir(dir),
         {:ok, db} <- EthStorage.RocksNative.open(dir, cf_names) do
      {:ok, %{db: db, dir: dir}}
    end
  end

  @impl true
  @spec get(map(), atom(), binary()) :: {:ok, binary() | nil} | {:error, term()}
  def get(%{db: db}, table, key) do
    with {:ok, cf_name} <- table_to_cf(table) do
      EthStorage.RocksNative.get(db, cf_name, key)
    end
  end

  @impl true
  @spec put(map(), atom(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def put(%{db: db} = state, table, key, value) do
    with {:ok, cf_name} <- table_to_cf(table) do
      case EthStorage.RocksNative.put(db, cf_name, key, value) do
        :ok -> {:ok, state}
        {:error, _} = err -> err
      end
    end
  end

  @impl true
  @spec delete(map(), atom(), binary()) :: {:ok, map()} | {:error, term()}
  def delete(%{db: db} = state, table, key) do
    with {:ok, cf_name} <- table_to_cf(table) do
      case EthStorage.RocksNative.delete(db, cf_name, key) do
        :ok -> {:ok, state}
        {:error, _} = err -> err
      end
    end
  end

  @impl true
  @spec batch_put(map(), [{atom(), binary(), binary()}]) :: {:ok, map()} | {:error, term()}
  def batch_put(%{db: db} = state, entries) do
    operations =
      Enum.reduce_while(entries, {:ok, []}, fn {table, key, value}, {:ok, acc} ->
        case table_to_cf(table) do
          {:ok, cf_name} -> {:cont, {:ok, [{cf_name, key, value} | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case operations do
      {:ok, ops} ->
        case EthStorage.RocksNative.batch_write(db, Enum.reverse(ops)) do
          :ok -> {:ok, state}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  @doc "Closes the RocksDB database, releasing all resources."
  @spec close(map()) :: :ok | {:error, term()}
  def close(%{db: db}) do
    EthStorage.RocksNative.close(db)
  end

  # --- Private helpers ---

  @spec ensure_dir(String.t()) :: :ok | {:error, term()}
  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  @spec table_to_cf(atom()) :: {:ok, String.t()} | {:error, :unknown_table}
  defp table_to_cf(table) when table in @tables do
    {:ok, Atom.to_string(table)}
  end

  defp table_to_cf(_table), do: {:error, :unknown_table}
end
