defmodule EthRpc.Eth do
  @moduledoc """
  Implements eth_, net_, web3_, and engine_ JSON-RPC namespace methods.

  Methods that require storage query the configured Store GenServer.
  When the Store is unavailable, sensible defaults are returned.
  """

  alias EthRpc.{Engine, Formatters, Hex}

  @type rpc_result :: {:ok, term()} | {:error, integer(), String.t()}

  # Map of method names to handler functions. Using a module attribute
  # keeps the dispatch function simple and under the complexity limit.
  @methods %{
    "eth_chainId" => :eth_chain_id,
    "eth_blockNumber" => :eth_block_number,
    "eth_getBalance" => :eth_get_balance,
    "eth_getTransactionCount" => :eth_get_transaction_count,
    "eth_getCode" => :eth_get_code,
    "eth_getStorageAt" => :eth_get_storage_at,
    "eth_call" => :eth_call,
    "eth_estimateGas" => :eth_estimate_gas,
    "eth_gasPrice" => :eth_gas_price,
    "eth_getBlockByNumber" => :eth_get_block_by_number,
    "eth_getBlockByHash" => :eth_get_block_by_hash,
    "eth_getTransactionByHash" => :eth_get_transaction_by_hash,
    "eth_getTransactionReceipt" => :eth_get_transaction_receipt,
    "eth_sendRawTransaction" => :eth_send_raw_transaction,
    "eth_syncing" => :eth_syncing,
    "eth_mining" => :eth_mining,
    "eth_accounts" => :eth_accounts,
    "net_version" => :net_version,
    "net_listening" => :net_listening,
    "net_peerCount" => :net_peer_count,
    "web3_clientVersion" => :web3_client_version,
    "web3_sha3" => :web3_sha3,
    "engine_forkchoiceUpdatedV3" => :engine_forkchoice_updated_v3,
    "engine_newPayloadV3" => :engine_new_payload_v3,
    "engine_getPayloadV3" => :engine_get_payload_v3,
    "engine_exchangeCapabilities" => :engine_exchange_capabilities
  }

  @doc """
  Dispatches a JSON-RPC method call to the appropriate handler.

  Returns `{:ok, result}` on success or `{:error, code, message}` on failure.
  """
  @spec handle(String.t(), list()) :: rpc_result()
  def handle(method, params) do
    case Map.fetch(@methods, method) do
      {:ok, handler} -> apply(__MODULE__, handler, [params])
      :error -> {:error, -32601, "Method not found"}
    end
  end

  # -- eth_ namespace ---------------------------------------------------------

  @doc false
  @spec eth_chain_id(list()) :: {:ok, String.t()}
  def eth_chain_id(_params), do: {:ok, "0x1"}

  @doc false
  @spec eth_block_number(list()) :: {:ok, String.t()}
  def eth_block_number(_params) do
    case store_call(:get_latest_block_number) do
      {:ok, nil} -> {:ok, "0x0"}
      {:ok, number} -> {:ok, Hex.encode_quantity(number)}
      _error -> {:ok, "0x0"}
    end
  end

  @doc false
  @spec eth_get_balance(list()) :: {:ok, String.t()}
  def eth_get_balance(params) do
    with {:ok, address_bin} <- parse_address(params) do
      case store_call(:get_account, [address_bin]) do
        {:ok, nil} ->
          {:ok, "0x0"}

        {:ok, encoded} when is_binary(encoded) ->
          account = :erlang.binary_to_term(encoded)
          {:ok, Formatters.format_balance(account.balance)}

        _error ->
          {:ok, "0x0"}
      end
    end
  end

  @doc false
  @spec eth_get_transaction_count(list()) :: {:ok, String.t()}
  def eth_get_transaction_count(params) do
    with {:ok, address_bin} <- parse_address(params) do
      case store_call(:get_account, [address_bin]) do
        {:ok, nil} ->
          {:ok, "0x0"}

        {:ok, encoded} when is_binary(encoded) ->
          account = :erlang.binary_to_term(encoded)
          {:ok, Hex.encode_quantity(account.nonce)}

        _error ->
          {:ok, "0x0"}
      end
    end
  end

  @doc false
  @spec eth_get_code(list()) :: {:ok, String.t()}
  def eth_get_code(params) do
    with {:ok, address_bin} <- parse_address(params) do
      case store_call(:get_account, [address_bin]) do
        {:ok, nil} ->
          {:ok, "0x"}

        {:ok, encoded} when is_binary(encoded) ->
          account = :erlang.binary_to_term(encoded)
          fetch_code(account.code_hash)

        _error ->
          {:ok, "0x"}
      end
    end
  end

  @doc false
  @spec eth_get_storage_at(list()) :: {:ok, String.t()}
  def eth_get_storage_at(_params) do
    {:ok, "0x" <> String.duplicate("0", 64)}
  end

  @doc false
  @spec eth_call(list()) :: {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_call([call_obj | _rest]) when is_map(call_obj) do
    call_params = parse_call_params(call_obj)
    {_mod, store_name} = store()

    case EthVm.CallExecutor.execute_call(call_params, store_name) do
      {:ok, output} ->
        {:ok, Hex.encode_data(output)}

      {:error, :execution_reverted} ->
        {:error, 3, "execution reverted"}

      {:error, reason} ->
        {:error, -32603, "Internal error: #{inspect(reason)}"}
    end
  end

  def eth_call(_params), do: {:ok, "0x"}

  @doc false
  @spec eth_estimate_gas(list()) :: {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_estimate_gas([call_obj | _rest]) when is_map(call_obj) do
    call_params = parse_call_params(call_obj)
    {_mod, store_name} = store()

    case EthVm.GasEstimator.estimate_gas(call_params, store_name) do
      {:ok, gas} ->
        {:ok, Hex.encode_quantity(gas)}

      {:error, :execution_reverted} ->
        {:error, 3, "execution reverted"}

      {:error, reason} ->
        {:error, -32603, "Internal error: #{inspect(reason)}"}
    end
  end

  def eth_estimate_gas(_params), do: {:ok, "0x5208"}

  @doc false
  @spec eth_gas_price(list()) :: {:ok, String.t()}
  def eth_gas_price(_params), do: {:ok, "0x3B9ACA00"}

  @doc false
  @spec eth_get_block_by_number(list()) :: {:ok, map() | nil}
  def eth_get_block_by_number(params) do
    with {:ok, block_number} <- parse_block_tag(params),
         {:ok, result} <- fetch_block_by_number(block_number) do
      format_block_result(result, full_txs?(params))
    else
      _error -> {:ok, nil}
    end
  end

  @doc false
  @spec eth_get_block_by_hash(list()) :: {:ok, map() | nil}
  def eth_get_block_by_hash(params) do
    with {:ok, hash_bin} <- parse_block_hash(params),
         {:ok, encoded} when not is_nil(encoded) <-
           store_call(:get_block_header, [hash_bin]) do
      header = :erlang.binary_to_term(encoded)
      full = full_txs?(params)
      {:ok, Formatters.format_block(header, full)}
    else
      _error -> {:ok, nil}
    end
  end

  @doc false
  @spec eth_get_transaction_by_hash(list()) :: {:ok, nil}
  def eth_get_transaction_by_hash(_params), do: {:ok, nil}

  @doc false
  @spec eth_get_transaction_receipt(list()) :: {:ok, nil}
  def eth_get_transaction_receipt(_params), do: {:ok, nil}

  @doc false
  @spec eth_send_raw_transaction(list()) ::
          {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_send_raw_transaction([raw_hex | _rest]) when is_binary(raw_hex) do
    with {:ok, raw_bytes} <- Hex.decode_data(raw_hex),
         {:ok, tx_hash} <- submit_raw_transaction(raw_bytes) do
      {:ok, Hex.encode_data(tx_hash)}
    else
      {:error, :invalid_hex} ->
        {:error, -32602, "Invalid params: expected hex-encoded transaction"}

      {:error, reason} ->
        {:error, -32603, "Transaction rejected: #{inspect(reason)}"}
    end
  end

  def eth_send_raw_transaction(_params) do
    {:error, -32602, "Invalid params: expected [hex_data]"}
  end

  @doc false
  @spec eth_syncing(list()) :: {:ok, false}
  def eth_syncing(_params), do: {:ok, false}

  @doc false
  @spec eth_mining(list()) :: {:ok, false}
  def eth_mining(_params), do: {:ok, false}

  @doc false
  @spec eth_accounts(list()) :: {:ok, list()}
  def eth_accounts(_params), do: {:ok, []}

  # -- net_ namespace --------------------------------------------------------

  @doc false
  @spec net_version(list()) :: {:ok, String.t()}
  def net_version(_params), do: {:ok, "1"}

  @doc false
  @spec net_listening(list()) :: {:ok, true}
  def net_listening(_params), do: {:ok, true}

  @doc false
  @spec net_peer_count(list()) :: {:ok, String.t()}
  def net_peer_count(_params), do: {:ok, "0x0"}

  # -- web3_ namespace -------------------------------------------------------

  @doc false
  @spec web3_client_version(list()) :: {:ok, String.t()}
  def web3_client_version(_params), do: {:ok, "ex_ethclient/0.1.0"}

  @doc false
  @spec web3_sha3(list()) :: rpc_result()
  def web3_sha3([data]) when is_binary(data) do
    with {:ok, bin} <- Hex.decode_data(data) do
      hash = EthCrypto.Hash.keccak256(bin)
      {:ok, Hex.encode_data(hash)}
    else
      {:error, :invalid_hex} ->
        {:error, -32602, "Invalid params: expected hex-encoded data"}
    end
  end

  def web3_sha3(_params) do
    {:error, -32602, "Invalid params: expected [data]"}
  end

  # -- engine_ namespace -----------------------------------------------------

  @doc false
  @spec engine_forkchoice_updated_v3(list()) :: {:ok, map()}
  def engine_forkchoice_updated_v3(params) do
    Engine.forkchoice_updated_v3(params)
  end

  @doc false
  @spec engine_new_payload_v3(list()) :: {:ok, map()}
  def engine_new_payload_v3(params) do
    Engine.new_payload_v3(params)
  end

  @doc false
  @spec engine_get_payload_v3(list()) :: rpc_result()
  def engine_get_payload_v3(params) do
    Engine.get_payload_v3(params)
  end

  @doc false
  @spec engine_exchange_capabilities(list()) :: {:ok, list()}
  def engine_exchange_capabilities(params) do
    Engine.exchange_capabilities(params)
  end

  # -- Private helpers -------------------------------------------------------

  @spec submit_raw_transaction(binary()) ::
          {:ok, <<_::256>>} | {:error, term()}
  defp submit_raw_transaction(raw_bytes) do
    if chain_available?() do
      EthChain.TxPipeline.submit_transaction(raw_bytes)
    else
      {:error, :chain_unavailable}
    end
  end

  @spec chain_available?() :: boolean()
  defp chain_available? do
    pid = GenServer.whereis(EthChain.Mempool)
    is_pid(pid) and Process.alive?(pid)
  end

  @spec store() :: {module(), GenServer.server()}
  defp store do
    case Application.get_env(:eth_rpc, :store) do
      nil -> {EthStorage.Store, EthStorage.Store}
      {mod, name} -> {mod, name}
      name -> {store_module(), name}
    end
  end

  @spec store_module() :: module()
  defp store_module do
    Application.get_env(:eth_rpc, :store_module, EthStorage.Store)
  end

  @spec store_available?() :: boolean()
  defp store_available? do
    {_mod, name} = store()
    pid = GenServer.whereis(name)
    is_pid(pid) and Process.alive?(pid)
  end

  @spec store_call(atom()) :: term()
  defp store_call(func) do
    store_call(func, [])
  end

  @spec store_call(atom(), list()) :: term()
  defp store_call(func, args) do
    if store_available?() do
      {mod, name} = store()
      apply(mod, func, [name | args])
    else
      {:error, :store_unavailable}
    end
  end

  @spec parse_address(list()) :: {:ok, binary()} | {:ok, String.t()}
  defp parse_address([address_hex | _rest]) when is_binary(address_hex) do
    case Hex.decode_data(address_hex) do
      {:ok, bin} -> {:ok, bin}
      {:error, _} -> {:ok, <<0::160>>}
    end
  end

  defp parse_address(_), do: {:ok, <<0::160>>}

  @spec parse_block_tag(list()) ::
          {:ok, non_neg_integer() | :latest | :earliest | :pending}
  defp parse_block_tag([tag | _rest]) when is_binary(tag) do
    case tag do
      "latest" -> {:ok, :latest}
      "earliest" -> {:ok, :earliest}
      "pending" -> {:ok, :pending}
      "0x" <> _ -> Hex.decode_quantity(tag)
      _ -> {:error, :invalid_block_tag}
    end
  end

  defp parse_block_tag(_), do: {:ok, :latest}

  @spec parse_block_hash(list()) ::
          {:ok, binary()} | {:error, :invalid_hex}
  defp parse_block_hash([hash_hex | _rest]) when is_binary(hash_hex) do
    Hex.decode_data(hash_hex)
  end

  defp parse_block_hash(_), do: {:error, :invalid_hex}

  @spec fetch_block_by_number(non_neg_integer() | :latest | :earliest | :pending) ::
          {:ok, {binary(), binary()} | nil} | {:error, term()}
  defp fetch_block_by_number(:latest) do
    case store_call(:get_latest_block_number) do
      {:ok, nil} -> {:ok, nil}
      {:ok, number} -> store_call(:get_block_by_number, [number])
      error -> error
    end
  end

  defp fetch_block_by_number(:earliest) do
    store_call(:get_block_by_number, [0])
  end

  defp fetch_block_by_number(:pending) do
    fetch_block_by_number(:latest)
  end

  defp fetch_block_by_number(number) when is_integer(number) do
    store_call(:get_block_by_number, [number])
  end

  @spec format_block_result(
          {binary(), binary()} | nil,
          boolean()
        ) :: {:ok, map() | nil}
  defp format_block_result(nil, _full_txs), do: {:ok, nil}

  defp format_block_result({header_bin, _body_bin}, full_txs) do
    header = :erlang.binary_to_term(header_bin)
    {:ok, Formatters.format_block(header, full_txs)}
  end

  @spec full_txs?(list()) :: boolean()
  defp full_txs?([_tag, true]), do: true
  defp full_txs?(_), do: false

  @spec parse_call_params(map()) :: map()
  defp parse_call_params(obj) when is_map(obj) do
    %{
      from: decode_address_field(obj, "from"),
      to: decode_address_field(obj, "to"),
      value: decode_quantity_field(obj, "value", 0),
      data: decode_data_field(obj, "data"),
      gas_price: decode_quantity_field(obj, "gasPrice", 0),
      max_fee_per_gas: decode_quantity_field(obj, "maxFeePerGas", 0)
    }
  end

  @spec decode_address_field(map(), String.t()) :: binary()
  defp decode_address_field(obj, key) do
    case Map.get(obj, key) do
      nil ->
        <<0::160>>

      hex ->
        case Hex.decode_data(hex) do
          {:ok, bin} -> bin
          _ -> <<0::160>>
        end
    end
  end

  @spec decode_quantity_field(map(), String.t(), non_neg_integer()) :: non_neg_integer()
  defp decode_quantity_field(obj, key, default) do
    case Map.get(obj, key) do
      nil ->
        default

      hex ->
        case Hex.decode_quantity(hex) do
          {:ok, val} -> val
          _ -> default
        end
    end
  end

  @spec decode_data_field(map(), String.t()) :: binary()
  defp decode_data_field(obj, key) do
    case Map.get(obj, key) do
      nil ->
        <<>>

      hex ->
        case Hex.decode_data(hex) do
          {:ok, bin} -> bin
          _ -> <<>>
        end
    end
  end

  @spec fetch_code(binary()) :: {:ok, String.t()}
  defp fetch_code(code_hash) do
    empty = EthCore.Types.Account.empty_code_hash()

    if code_hash == empty do
      {:ok, "0x"}
    else
      case store_call(:get_account_code, [code_hash]) do
        {:ok, nil} -> {:ok, "0x"}
        {:ok, code} -> {:ok, Hex.encode_data(code)}
        _error -> {:ok, "0x"}
      end
    end
  end
end
