defmodule EthRpc.TestStore do
  @moduledoc false
  # Simple in-memory GenServer store for testing RPC handlers.
  # Mimics the EthStorage.Store API without depending on eth_storage.

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_block_header(GenServer.server(), binary()) ::
          {:ok, binary() | nil}
  def get_block_header(server, hash) do
    GenServer.call(server, {:get, :headers, hash})
  end

  @spec put_block_header(GenServer.server(), binary(), binary()) :: :ok
  def put_block_header(server, hash, data) do
    GenServer.call(server, {:put, :headers, hash, data})
  end

  @spec get_block_body(GenServer.server(), binary()) ::
          {:ok, binary() | nil}
  def get_block_body(server, hash) do
    GenServer.call(server, {:get, :bodies, hash})
  end

  @spec put_block_body(GenServer.server(), binary(), binary()) :: :ok
  def put_block_body(server, hash, data) do
    GenServer.call(server, {:put, :bodies, hash, data})
  end

  @spec get_block_by_number(GenServer.server(), non_neg_integer()) ::
          {:ok, {binary(), binary()} | nil}
  def get_block_by_number(server, number) do
    GenServer.call(server, {:get_block_by_number, number})
  end

  @spec get_canonical_hash(GenServer.server(), non_neg_integer()) ::
          {:ok, binary() | nil}
  def get_canonical_hash(server, number) do
    GenServer.call(server, {:get, :canonical_hashes, number})
  end

  @spec set_canonical_hash(
          GenServer.server(),
          non_neg_integer(),
          binary()
        ) :: :ok
  def set_canonical_hash(server, number, hash) do
    GenServer.call(server, {:put, :canonical_hashes, number, hash})
  end

  @spec get_latest_block_number(GenServer.server()) ::
          {:ok, non_neg_integer() | nil}
  def get_latest_block_number(server) do
    GenServer.call(server, {:get_latest_block_number})
  end

  @spec set_latest_block_number(
          GenServer.server(),
          non_neg_integer()
        ) :: :ok
  def set_latest_block_number(server, number) do
    GenServer.call(server, {:set_latest_block_number, number})
  end

  @spec get_account(GenServer.server(), binary()) ::
          {:ok, binary() | nil}
  def get_account(server, address_hash) do
    GenServer.call(server, {:get, :accounts, address_hash})
  end

  @spec put_account(GenServer.server(), binary(), binary()) :: :ok
  def put_account(server, address_hash, data) do
    GenServer.call(server, {:put, :accounts, address_hash, data})
  end

  @spec get_account_code(GenServer.server(), binary()) ::
          {:ok, binary() | nil}
  def get_account_code(server, code_hash) do
    GenServer.call(server, {:get, :codes, code_hash})
  end

  @spec put_account_code(GenServer.server(), binary(), binary()) :: :ok
  def put_account_code(server, code_hash, code) do
    GenServer.call(server, {:put, :codes, code_hash, code})
  end

  @spec get_receipt(GenServer.server(), binary(), non_neg_integer()) ::
          {:ok, binary() | nil}
  def get_receipt(server, block_hash, tx_index) do
    key = {block_hash, tx_index}
    GenServer.call(server, {:get, :receipts, key})
  end

  @spec put_receipt(GenServer.server(), binary(), non_neg_integer(), binary()) :: :ok
  def put_receipt(server, block_hash, tx_index, data) do
    key = {block_hash, tx_index}
    GenServer.call(server, {:put, :receipts, key, data})
  end

  @spec get_storage_trie_node(GenServer.server(), binary()) ::
          {:ok, binary() | nil}
  def get_storage_trie_node(server, key) do
    GenServer.call(server, {:get, :storage_trie_nodes, key})
  end

  @spec put_storage_trie_node(GenServer.server(), binary(), binary()) :: :ok
  def put_storage_trie_node(server, key, value) do
    GenServer.call(server, {:put, :storage_trie_nodes, key, value})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{data: %{}, latest_block_number: nil}}
  end

  @impl true
  def handle_call({:get, table, key}, _from, state) do
    val = get_in(state, [:data, {table, key}])
    {:reply, {:ok, val}, state}
  end

  @impl true
  def handle_call({:put, table, key, value}, _from, state) do
    new_state = put_in(state, [:data, {table, key}], value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get_latest_block_number}, _from, state) do
    {:reply, {:ok, state.latest_block_number}, state}
  end

  @impl true
  def handle_call({:set_latest_block_number, number}, _from, state) do
    {:reply, :ok, %{state | latest_block_number: number}}
  end

  @impl true
  def handle_call({:get_block_by_number, number}, _from, state) do
    case get_in(state, [:data, {:canonical_hashes, number}]) do
      nil ->
        {:reply, {:ok, nil}, state}

      hash ->
        header = get_in(state, [:data, {:headers, hash}])
        body = get_in(state, [:data, {:bodies, hash}])

        if header do
          {:reply, {:ok, {header, body}}, state}
        else
          {:reply, {:ok, nil}, state}
        end
    end
  end
end
