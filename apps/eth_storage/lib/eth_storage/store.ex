defmodule EthStorage.Store do
  @moduledoc """
  High-level storage API wrapping a backend.

  GenServer that holds backend state and provides typed access functions
  for blocks, headers, accounts, trie nodes, and chain configuration.
  """

  use GenServer

  # --- Public API ---

  @doc "Starts the Store GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Gets a block header by hash."
  @spec get_block_header(GenServer.server(), <<_::256>>) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_block_header(server \\ __MODULE__, hash) do
    GenServer.call(server, {:get, :headers, hash})
  end

  @doc "Stores a block header keyed by hash."
  @spec put_block_header(GenServer.server(), <<_::256>>, binary()) ::
          :ok | {:error, term()}
  def put_block_header(server \\ __MODULE__, hash, encoded_header) do
    GenServer.call(server, {:put, :headers, hash, encoded_header})
  end

  @doc "Gets a block body by hash."
  @spec get_block_body(GenServer.server(), <<_::256>>) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_block_body(server \\ __MODULE__, hash) do
    GenServer.call(server, {:get, :bodies, hash})
  end

  @doc "Stores a block body keyed by hash."
  @spec put_block_body(GenServer.server(), <<_::256>>, binary()) ::
          :ok | {:error, term()}
  def put_block_body(server \\ __MODULE__, hash, encoded_body) do
    GenServer.call(server, {:put, :bodies, hash, encoded_body})
  end

  @doc "Gets a block by number via canonical hash lookup."
  @spec get_block_by_number(GenServer.server(), non_neg_integer()) ::
          {:ok, {binary(), binary()} | nil} | {:error, term()}
  def get_block_by_number(server \\ __MODULE__, number) do
    GenServer.call(server, {:get_block_by_number, number})
  end

  @doc "Gets the canonical hash for a block number."
  @spec get_canonical_hash(GenServer.server(), non_neg_integer()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_canonical_hash(server \\ __MODULE__, number) do
    GenServer.call(server, {:get, :canonical_hashes, encode_number(number)})
  end

  @doc "Sets the canonical hash for a block number."
  @spec set_canonical_hash(GenServer.server(), non_neg_integer(), <<_::256>>) ::
          :ok | {:error, term()}
  def set_canonical_hash(server \\ __MODULE__, number, hash) do
    GenServer.call(
      server,
      {:put, :canonical_hashes, encode_number(number), hash}
    )
  end

  @doc "Gets the latest block number."
  @spec get_latest_block_number(GenServer.server()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  def get_latest_block_number(server \\ __MODULE__) do
    case GenServer.call(server, {:get, :chain_config, "latest_block_number"}) do
      {:ok, nil} -> {:ok, nil}
      {:ok, bin} -> {:ok, :binary.decode_unsigned(bin)}
      {:error, _} = err -> err
    end
  end

  @doc "Sets the latest block number."
  @spec set_latest_block_number(GenServer.server(), non_neg_integer()) ::
          :ok | {:error, term()}
  def set_latest_block_number(server \\ __MODULE__, number) do
    GenServer.call(
      server,
      {:put, :chain_config, "latest_block_number", :binary.encode_unsigned(number)}
    )
  end

  @doc "Gets an account from the account trie by address hash."
  @spec get_account(GenServer.server(), binary()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_account(server \\ __MODULE__, address_hash) do
    GenServer.call(server, {:get, :account_trie_nodes, address_hash})
  end

  @doc "Stores an account in the account trie by address hash."
  @spec put_account(GenServer.server(), binary(), binary()) ::
          :ok | {:error, term()}
  def put_account(server \\ __MODULE__, address_hash, encoded_account) do
    GenServer.call(
      server,
      {:put, :account_trie_nodes, address_hash, encoded_account}
    )
  end

  @doc "Gets account bytecode by code hash."
  @spec get_account_code(GenServer.server(), <<_::256>>) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_account_code(server \\ __MODULE__, code_hash) do
    GenServer.call(server, {:get, :account_codes, code_hash})
  end

  @doc "Stores account bytecode keyed by code hash."
  @spec put_account_code(GenServer.server(), <<_::256>>, binary()) ::
          :ok | {:error, term()}
  def put_account_code(server \\ __MODULE__, code_hash, code) do
    GenServer.call(server, {:put, :account_codes, code_hash, code})
  end

  @doc "Stores a transaction location (block hash + index) keyed by tx hash."
  @spec put_tx_location(GenServer.server(), <<_::256>>, <<_::256>>, non_neg_integer()) ::
          :ok | {:error, term()}
  def put_tx_location(server \\ __MODULE__, tx_hash, block_hash, tx_index) do
    value = :erlang.term_to_binary({block_hash, tx_index})
    GenServer.call(server, {:put, :tx_locations, tx_hash, value})
  end

  @doc "Gets a transaction location by tx hash. Returns `{block_hash, tx_index}` or nil."
  @spec get_tx_location(GenServer.server(), <<_::256>>) ::
          {:ok, {<<_::256>>, non_neg_integer()} | nil} | {:error, term()}
  def get_tx_location(server \\ __MODULE__, tx_hash) do
    case GenServer.call(server, {:get, :tx_locations, tx_hash}) do
      {:ok, nil} -> {:ok, nil}
      {:ok, bin} -> {:ok, :erlang.binary_to_term(bin)}
      {:error, _} = err -> err
    end
  end

  @doc "Gets a receipt by block hash and transaction index."
  @spec get_receipt(GenServer.server(), <<_::256>>, non_neg_integer()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_receipt(server \\ __MODULE__, block_hash, tx_index) do
    key = :erlang.term_to_binary({block_hash, tx_index})
    GenServer.call(server, {:get, :receipts, key})
  end

  @doc "Stores a receipt for a given block hash and transaction index."
  @spec put_receipt(
          GenServer.server(),
          <<_::256>>,
          non_neg_integer(),
          binary()
        ) :: :ok | {:error, term()}
  def put_receipt(server \\ __MODULE__, block_hash, tx_index, encoded_receipt) do
    key = :erlang.term_to_binary({block_hash, tx_index})
    GenServer.call(server, {:put, :receipts, key, encoded_receipt})
  end

  @doc "Stores a blob and its KZG proof keyed by versioned hash."
  @spec put_blob(GenServer.server(), <<_::256>>, {binary(), binary()}) ::
          :ok | {:error, term()}
  def put_blob(server \\ __MODULE__, versioned_hash, {blob_data, kzg_proof}) do
    value = :erlang.term_to_binary({blob_data, kzg_proof})
    GenServer.call(server, {:put, :blobs, versioned_hash, value})
  end

  @doc "Gets a blob and its KZG proof by versioned hash. Returns `{blob_data, kzg_proof}` or nil."
  @spec get_blob(GenServer.server(), <<_::256>>) ::
          {:ok, {binary(), binary()} | nil} | {:error, term()}
  def get_blob(server \\ __MODULE__, versioned_hash) do
    case GenServer.call(server, {:get, :blobs, versioned_hash}) do
      {:ok, nil} -> {:ok, nil}
      {:ok, bin} -> {:ok, :erlang.binary_to_term(bin)}
      {:error, _} = err -> err
    end
  end

  @doc "Gets an account trie node by hash."
  @spec get_trie_node(GenServer.server(), <<_::256>>) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_trie_node(server \\ __MODULE__, node_hash) do
    GenServer.call(server, {:get, :account_trie_nodes, node_hash})
  end

  @doc "Stores an account trie node by hash."
  @spec put_trie_node(GenServer.server(), <<_::256>>, binary()) ::
          :ok | {:error, term()}
  def put_trie_node(server \\ __MODULE__, node_hash, encoded_node) do
    GenServer.call(
      server,
      {:put, :account_trie_nodes, node_hash, encoded_node}
    )
  end

  @doc "Gets a storage trie node by hash."
  @spec get_storage_trie_node(GenServer.server(), <<_::256>>) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_storage_trie_node(server \\ __MODULE__, node_hash) do
    GenServer.call(server, {:get, :storage_trie_nodes, node_hash})
  end

  @doc "Stores a storage trie node by hash."
  @spec put_storage_trie_node(GenServer.server(), <<_::256>>, binary()) ::
          :ok | {:error, term()}
  def put_storage_trie_node(server \\ __MODULE__, node_hash, encoded_node) do
    GenServer.call(
      server,
      {:put, :storage_trie_nodes, node_hash, encoded_node}
    )
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()} | {:stop, term()}
  def init(opts) do
    default_backend = Application.get_env(:eth_storage, :backend, EthStorage.Backend.Memory)
    default_backend_opts = Application.get_env(:eth_storage, :backend_opts, [])

    backend = Keyword.get(opts, :backend, default_backend)
    backend_opts = Keyword.get(opts, :backend_opts, default_backend_opts)

    # Merge top-level opts (e.g. :datadir) for backward compatibility
    merged_opts =
      Keyword.merge(backend_opts, Keyword.drop(opts, [:name, :backend, :backend_opts]))

    case backend.init(merged_opts) do
      {:ok, backend_state} ->
        {:ok, %{backend: backend, backend_state: backend_state}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get, table, key}, _from, state) do
    %{backend: backend, backend_state: backend_state} = state
    {:reply, backend.get(backend_state, table, key), state}
  end

  @impl true
  def handle_call({:put, table, key, value}, _from, state) do
    %{backend: backend, backend_state: backend_state} = state

    case backend.put(backend_state, table, key, value) do
      {:ok, new_backend_state} ->
        {:reply, :ok, %{state | backend_state: new_backend_state}}

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl true
  def handle_call({:get_block_by_number, number}, _from, state) do
    %{backend: backend, backend_state: bs} = state

    result =
      with {:ok, hash} when not is_nil(hash) <-
             backend.get(bs, :canonical_hashes, encode_number(number)),
           {:ok, header} <- backend.get(bs, :headers, hash),
           {:ok, body} <- backend.get(bs, :bodies, hash) do
        if header do
          {:ok, {header, body}}
        else
          {:ok, nil}
        end
      else
        {:ok, nil} -> {:ok, nil}
        {:error, _} = err -> err
      end

    {:reply, result, state}
  end

  @spec encode_number(non_neg_integer()) :: binary()
  defp encode_number(number), do: :binary.encode_unsigned(number)
end
