defmodule EthStorage.Backend do
  @moduledoc """
  Behaviour defining the storage backend interface.

  All storage backends (memory, RocksDB, etc.) must implement these callbacks
  to provide a uniform key-value storage API with logical table separation.
  """

  @type key :: binary()
  @type value :: binary()
  @type table :: atom()

  @doc "Initializes the backend with the given options."
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, term()}

  @doc "Gets a value by table and key. Returns `{:ok, nil}` if not found."
  @callback get(state :: term(), table(), key()) ::
              {:ok, value() | nil} | {:error, term()}

  @doc "Puts a key-value pair into a table."
  @callback put(state :: term(), table(), key(), value()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc "Deletes a key from a table."
  @callback delete(state :: term(), table(), key()) ::
              {:ok, state :: term()} | {:error, term()}

  @doc "Puts multiple key-value pairs atomically."
  @callback batch_put(state :: term(), [{table(), key(), value()}]) ::
              {:ok, state :: term()} | {:error, term()}

  @doc "Returns the number of entries in a table."
  @callback count(state :: term(), table()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc "Flushes any buffered writes to persistent storage. No-op for in-memory backends."
  @callback flush(state :: term()) :: :ok | {:error, term()}

  @optional_callbacks flush: 1, count: 2
end
