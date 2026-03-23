defmodule EthStorage.RocksNative do
  @moduledoc """
  Rust NIF bindings for RocksDB storage operations.

  Provides low-level access to a RocksDB database through Rust NIFs.
  Column families are used to separate logical tables within a single database.
  """

  use Rustler,
    otp_app: :eth_storage,
    crate: "rocks_native"

  @doc "Opens a RocksDB database at the given path with the specified column families."
  @spec open(String.t(), [String.t()]) :: {:ok, reference()} | {:error, term()}
  def open(_path, _column_families), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Gets a value from the specified column family by key."
  @spec get(reference(), String.t(), binary()) :: {:ok, binary() | nil} | {:error, term()}
  def get(_db, _cf, _key), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Puts a key-value pair into the specified column family."
  @spec put(reference(), String.t(), binary(), binary()) :: :ok | {:error, term()}
  def put(_db, _cf, _key, _value), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Deletes a key from the specified column family."
  @spec delete(reference(), String.t(), binary()) :: :ok | {:error, term()}
  def delete(_db, _cf, _key), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Writes a batch of operations atomically. Each operation is {cf_name, key, value}."
  @spec batch_write(reference(), [{String.t(), binary(), binary()}]) :: :ok | {:error, term()}
  def batch_write(_db, _operations), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Closes the RocksDB database, releasing all resources."
  @spec close(reference()) :: :ok | {:error, term()}
  def close(_db), do: :erlang.nif_error(:nif_not_loaded)
end
