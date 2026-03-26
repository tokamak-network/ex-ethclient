defmodule EthStorage.Backend.DETS do
  @moduledoc """
  DETS-based persistent storage backend.

  Creates one DETS file per logical table in the configured data directory.
  Suitable for single-node persistent storage without external dependencies.
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
  @spec init(keyword()) :: {:ok, map()} | {:error, term()}
  def init(opts) do
    dir = Keyword.get(opts, :datadir, "./data/storage")

    with :ok <- ensure_dir(dir) do
      open_tables(dir)
    end
  end

  @impl true
  @spec get(map(), atom(), binary()) :: {:ok, binary() | nil} | {:error, term()}
  def get(state, table, key) do
    with {:ok, tab} <- lookup_table(state, table) do
      case :dets.lookup(tab, key) do
        [{^key, value}] -> {:ok, value}
        [] -> {:ok, nil}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  @spec put(map(), atom(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def put(state, table, key, value) do
    with {:ok, tab} <- lookup_table(state, table) do
      case :dets.insert(tab, {key, value}) do
        :ok -> {:ok, state}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  @spec delete(map(), atom(), binary()) :: {:ok, map()} | {:error, term()}
  def delete(state, table, key) do
    with {:ok, tab} <- lookup_table(state, table) do
      case :dets.delete(tab, key) do
        :ok -> {:ok, state}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  @spec batch_put(map(), [{atom(), binary(), binary()}]) ::
          {:ok, map()} | {:error, term()}
  def batch_put(state, entries) do
    grouped = Enum.group_by(entries, &elem(&1, 0))

    result =
      Enum.reduce_while(grouped, :ok, fn {table, items}, :ok ->
        case lookup_table(state, table) do
          {:ok, tab} ->
            objects = Enum.map(items, fn {_table, key, value} -> {key, value} end)

            case :dets.insert(tab, objects) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case result do
      :ok -> {:ok, state}
      {:error, _} = err -> err
    end
  end

  @doc "Closes all DETS tables."
  @spec close(map()) :: :ok
  def close(%{tables: tables}) do
    Enum.each(tables, fn {_name, tab} -> :dets.close(tab) end)
    :ok
  end

  # --- Private helpers ---

  @spec ensure_dir(String.t()) :: :ok | {:error, term()}
  defp ensure_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  @spec open_tables(String.t()) :: {:ok, map()} | {:error, term()}
  defp open_tables(dir) do
    # Use a unique suffix to avoid DETS name collisions across instances
    suffix = :erlang.unique_integer([:positive])

    result =
      Enum.reduce_while(@tables, {:ok, %{}}, fn name, {:ok, acc} ->
        file = Path.join(dir, "#{name}.dets") |> String.to_charlist()
        dets_name = :"dets_#{name}_#{suffix}"

        case :dets.open_file(dets_name, file: file, type: :set, auto_save: 60_000) do
          {:ok, tab} ->
            {:cont, {:ok, Map.put(acc, name, tab)}}

          {:error, reason} ->
            # Close any already-opened tables before returning error
            Enum.each(acc, fn {_n, t} -> :dets.close(t) end)
            {:halt, {:error, {:dets_open_failed, name, reason}}}
        end
      end)

    case result do
      {:ok, tables_map} -> {:ok, %{dir: dir, tables: tables_map}}
      {:error, _} = err -> err
    end
  end

  @spec lookup_table(map(), atom()) ::
          {:ok, :dets.tab_name()} | {:error, :unknown_table}
  defp lookup_table(%{tables: tables}, table) do
    case Map.fetch(tables, table) do
      {:ok, tab} -> {:ok, tab}
      :error -> {:error, :unknown_table}
    end
  end
end
