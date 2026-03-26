defmodule EthRpc.Eth do
  @moduledoc """
  Implements eth_, net_, web3_, and engine_ JSON-RPC namespace methods.

  Methods that require storage query the configured Store GenServer.
  When the Store is unavailable, sensible defaults are returned.
  """

  alias EthCore.Types.{SignedTransaction, Transaction}
  alias EthRpc.{Engine, FilterManager, Formatters, Hex, LogQuery}

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
    "eth_getBlockTransactionCountByNumber" => :eth_get_block_tx_count_by_number,
    "eth_getBlockTransactionCountByHash" => :eth_get_block_tx_count_by_hash,
    "eth_getTransactionByHash" => :eth_get_transaction_by_hash,
    "eth_getTransactionByBlockNumberAndIndex" => :eth_get_tx_by_block_number_and_index,
    "eth_getTransactionByBlockHashAndIndex" => :eth_get_tx_by_block_hash_and_index,
    "eth_getTransactionReceipt" => :eth_get_transaction_receipt,
    "eth_getBlockReceipts" => :eth_get_block_receipts,
    "eth_sendRawTransaction" => :eth_send_raw_transaction,
    "eth_syncing" => :eth_syncing,
    "eth_mining" => :eth_mining,
    "eth_accounts" => :eth_accounts,
    "net_version" => :net_version,
    "net_listening" => :net_listening,
    "net_peerCount" => :net_peer_count,
    "web3_clientVersion" => :web3_client_version,
    "web3_sha3" => :web3_sha3,
    "eth_getLogs" => :eth_get_logs,
    "eth_newFilter" => :eth_new_filter,
    "eth_newBlockFilter" => :eth_new_block_filter,
    "eth_newPendingTransactionFilter" => :eth_new_pending_transaction_filter,
    "eth_getFilterChanges" => :eth_get_filter_changes,
    "eth_getFilterLogs" => :eth_get_filter_logs,
    "eth_uninstallFilter" => :eth_uninstall_filter,
    "eth_getProof" => :eth_get_proof,
    "engine_forkchoiceUpdatedV1" => :engine_forkchoice_updated_v1,
    "engine_forkchoiceUpdatedV2" => :engine_forkchoice_updated_v2,
    "engine_forkchoiceUpdatedV3" => :engine_forkchoice_updated_v3,
    "engine_forkchoiceUpdatedV4" => :engine_forkchoice_updated_v4,
    "engine_newPayloadV1" => :engine_new_payload_v1,
    "engine_newPayloadV2" => :engine_new_payload_v2,
    "engine_newPayloadV3" => :engine_new_payload_v3,
    "engine_newPayloadV4" => :engine_new_payload_v4,
    "engine_getPayloadV1" => :engine_get_payload_v1,
    "engine_getPayloadV2" => :engine_get_payload_v2,
    "engine_getPayloadV3" => :engine_get_payload_v3,
    "engine_getPayloadV4" => :engine_get_payload_v4,
    "engine_getPayloadBodiesByHashV1" => :engine_get_payload_bodies_by_hash_v1,
    "engine_getPayloadBodiesByHashV2" => :engine_get_payload_bodies_by_hash_v2,
    "engine_getPayloadBodiesByRangeV1" => :engine_get_payload_bodies_by_range_v1,
    "engine_getPayloadBodiesByRangeV2" => :engine_get_payload_bodies_by_range_v2,
    "engine_getBlobsV1" => :engine_get_blobs_v1,
    "engine_getClientVersionV1" => :engine_get_client_version_v1,
    "engine_exchangeTransitionConfigurationV1" => :engine_exchange_transition_config_v1,
    "engine_exchangeCapabilities" => :engine_exchange_capabilities,
    "eth_feeHistory" => :eth_fee_history,
    "eth_maxPriorityFeePerGas" => :eth_max_priority_fee_per_gas,
    "eth_blobBaseFee" => :eth_blob_base_fee,
    "eth_createAccessList" => :eth_create_access_list,
    "eth_sendTransaction" => :eth_send_transaction,
    "debug_getRawHeader" => :debug_get_raw_header,
    "debug_getRawBlock" => :debug_get_raw_block,
    "debug_getRawTransaction" => :debug_get_raw_transaction,
    "debug_getRawReceipts" => :debug_get_raw_receipts,
    "admin_nodeInfo" => :admin_node_info,
    "admin_peers" => :admin_peers,
    "admin_addPeer" => :admin_add_peer,
    "admin_setLogLevel" => :admin_set_log_level,
    "txpool_content" => :txpool_content,
    "txpool_status" => :txpool_status
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
  def eth_chain_id(_params) do
    chain_id = Application.get_env(:eth_chain, :chain_id, 1)
    {:ok, Hex.encode_quantity(chain_id)}
  end

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
  def eth_get_storage_at([address_hex, slot_hex | _rest])
      when is_binary(address_hex) and is_binary(slot_hex) do
    zero_value = "0x" <> String.duplicate("0", 64)

    with {:ok, address_bin} <- Hex.decode_data(address_hex),
         {:ok, slot_bin} <- decode_storage_slot(slot_hex) do
      case store_call(:get_storage_trie_node, [storage_key(address_bin, slot_bin)]) do
        {:ok, nil} ->
          {:ok, zero_value}

        {:ok, value} when is_binary(value) ->
          {:ok, Hex.encode_data(pad_to_32(value))}

        _error ->
          {:ok, zero_value}
      end
    else
      _error -> {:ok, zero_value}
    end
  end

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
  def eth_gas_price(_params) do
    if store_available?() do
      {_mod, name} = store()

      case EthChain.GasOracle.suggest_gas_price(name) do
        {:ok, price} -> {:ok, Hex.encode_quantity(price)}
        _ -> {:ok, "0x3b9aca00"}
      end
    else
      {:ok, "0x3b9aca00"}
    end
  end

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
      txs = fetch_block_transactions(hash_bin)
      {:ok, Formatters.format_block(header, txs, full)}
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns the number of transactions in a block matching the given block number.
  """
  @spec eth_get_block_tx_count_by_number(list()) :: {:ok, String.t() | nil}
  def eth_get_block_tx_count_by_number(params) do
    with {:ok, block_number} <- parse_block_tag(params),
         {:ok, result} <- fetch_block_by_number(block_number) do
      count_block_transactions(result)
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns the number of transactions in a block matching the given block hash.
  """
  @spec eth_get_block_tx_count_by_hash(list()) :: {:ok, String.t() | nil}
  def eth_get_block_tx_count_by_hash(params) do
    with {:ok, hash_bin} <- parse_block_hash(params),
         {:ok, body_bin} when not is_nil(body_bin) <-
           store_call(:get_block_body, [hash_bin]) do
      body = :erlang.binary_to_term(body_bin)
      {:ok, Hex.encode_quantity(length(body.transactions))}
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns information about a transaction by block number and index.
  """
  @spec eth_get_tx_by_block_number_and_index(list()) :: {:ok, map() | nil}
  def eth_get_tx_by_block_number_and_index(params) do
    with {:ok, block_number} <- parse_block_tag(params),
         {:ok, tx_index} <- parse_tx_index(params),
         {:ok, result} <- fetch_block_by_number(block_number) do
      get_tx_at_index(result, tx_index)
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns information about a transaction by block hash and index.
  """
  @spec eth_get_tx_by_block_hash_and_index(list()) :: {:ok, map() | nil}
  def eth_get_tx_by_block_hash_and_index(params) do
    with {:ok, hash_bin} <- parse_block_hash(params),
         {:ok, tx_index} <- parse_tx_index(params),
         {:ok, header_bin} when not is_nil(header_bin) <-
           store_call(:get_block_header, [hash_bin]),
         {:ok, body_bin} when not is_nil(body_bin) <-
           store_call(:get_block_body, [hash_bin]) do
      header = :erlang.binary_to_term(header_bin)
      body = :erlang.binary_to_term(body_bin)

      case Enum.at(body.transactions, tx_index) do
        nil ->
          {:ok, nil}

        signed_tx ->
          {:ok,
           Formatters.format_transaction(signed_tx, %{
             block_hash: hash_bin,
             block_number: header.number,
             tx_index: tx_index
           })}
      end
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns the transaction for the given hash, looked up via the tx location index.
  """
  @spec eth_get_transaction_by_hash(list()) :: {:ok, map() | nil}
  def eth_get_transaction_by_hash(params) do
    with {:ok, tx_hash} <- parse_block_hash(params),
         {:ok, {block_hash, tx_index}} <- lookup_tx_location(tx_hash),
         {:ok, header_bin} when not is_nil(header_bin) <-
           store_call(:get_block_header, [block_hash]),
         {:ok, body_bin} when not is_nil(body_bin) <-
           store_call(:get_block_body, [block_hash]) do
      header = :erlang.binary_to_term(header_bin)
      body = :erlang.binary_to_term(body_bin)

      case Enum.at(body.transactions, tx_index) do
        nil ->
          {:ok, nil}

        signed_tx ->
          {:ok,
           Formatters.format_transaction(signed_tx, %{
             block_hash: block_hash,
             block_number: header.number,
             tx_index: tx_index
           })}
      end
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns the receipt of a transaction by transaction hash.
  """
  @spec eth_get_transaction_receipt(list()) :: {:ok, map() | nil}
  def eth_get_transaction_receipt(params) do
    with {:ok, tx_hash} <- parse_block_hash(params),
         {:ok, {block_hash, tx_index}} <- lookup_tx_location(tx_hash),
         {:ok, header_bin} when not is_nil(header_bin) <-
           store_call(:get_block_header, [block_hash]),
         {:ok, body_bin} when not is_nil(body_bin) <-
           store_call(:get_block_body, [block_hash]),
         {:ok, receipt_bin} when not is_nil(receipt_bin) <-
           store_call(:get_receipt, [block_hash, tx_index]) do
      header = :erlang.binary_to_term(header_bin)
      body = :erlang.binary_to_term(body_bin)
      receipt = :erlang.binary_to_term(receipt_bin)
      signed_tx = Enum.at(body.transactions, tx_index)

      from_addr = recover_tx_sender(signed_tx)
      to_addr = tx_to_field(signed_tx)

      {:ok,
       Formatters.format_full_receipt(receipt, %{
         tx_hash: tx_hash,
         tx_index: tx_index,
         block_hash: block_hash,
         block_number: header.number,
         from: from_addr,
         to: to_addr,
         gas_used: receipt.cumulative_gas_used,
         contract_address: nil
       })}
    else
      _error -> {:ok, nil}
    end
  end

  @doc """
  Returns all receipts for a block by number tag.
  """
  @spec eth_get_block_receipts(list()) :: {:ok, list() | nil}
  def eth_get_block_receipts(params) do
    with {:ok, block_number} <- parse_block_tag(params),
         {:ok, result} <- fetch_block_by_number(block_number) do
      format_block_receipts(result)
    else
      _error -> {:ok, nil}
    end
  end

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

  @doc """
  Returns sync status. If syncing, returns starting/current/highest block numbers.
  If synced or idle, returns false.
  """
  @spec eth_syncing(list()) :: {:ok, false | map()}
  def eth_syncing(_params) do
    if sync_manager_available?() do
      status = apply(EthNet.Sync.Manager, :status, [])

      if status.status == :syncing do
        {:ok,
         %{
           "startingBlock" => Hex.encode_quantity(0),
           "currentBlock" => Hex.encode_quantity(status.current_block),
           "highestBlock" => Hex.encode_quantity(status.target_block)
         }}
      else
        {:ok, false}
      end
    else
      {:ok, false}
    end
  end

  @doc false
  @spec eth_mining(list()) :: {:ok, false}
  def eth_mining(_params), do: {:ok, false}

  @doc false
  @spec eth_accounts(list()) :: {:ok, list()}
  def eth_accounts(_params), do: {:ok, []}

  # -- Log & Filter methods --------------------------------------------------

  @doc false
  @spec eth_get_logs(list()) :: {:ok, [map()]} | {:error, integer(), String.t()}
  def eth_get_logs([filter_obj | _rest]) when is_map(filter_obj) do
    filter = parse_log_filter(filter_obj)

    case store_available?() do
      true ->
        {_mod, name} = store()
        LogQuery.query_logs(filter, name)

      false ->
        {:ok, []}
    end
  end

  def eth_get_logs(_params) do
    {:error, -32602, "Invalid params: expected [filter_object]"}
  end

  @doc false
  @spec eth_new_filter(list()) :: {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_new_filter([filter_obj | _rest]) when is_map(filter_obj) do
    filter = parse_log_filter(filter_obj)

    if filter_manager_available?() do
      FilterManager.new_filter(filter)
    else
      {:error, -32603, "Filter manager not available"}
    end
  end

  def eth_new_filter(_params) do
    {:error, -32602, "Invalid params: expected [filter_object]"}
  end

  @doc false
  @spec eth_new_block_filter(list()) :: {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_new_block_filter(_params) do
    if filter_manager_available?() do
      FilterManager.new_block_filter()
    else
      {:error, -32603, "Filter manager not available"}
    end
  end

  @doc false
  @spec eth_new_pending_transaction_filter(list()) ::
          {:ok, String.t()} | {:error, integer(), String.t()}
  def eth_new_pending_transaction_filter(_params) do
    if filter_manager_available?() do
      FilterManager.new_pending_tx_filter()
    else
      {:error, -32603, "Filter manager not available"}
    end
  end

  @doc false
  @spec eth_get_filter_changes(list()) ::
          {:ok, [term()]} | {:error, integer(), String.t()}
  def eth_get_filter_changes([filter_id | _rest]) when is_binary(filter_id) do
    if filter_manager_available?() do
      case FilterManager.get_filter_changes(filter_id) do
        {:ok, changes} -> {:ok, changes}
        {:error, :not_found} -> {:error, -32000, "Filter not found"}
      end
    else
      {:error, -32603, "Filter manager not available"}
    end
  end

  def eth_get_filter_changes(_params) do
    {:error, -32602, "Invalid params: expected [filter_id]"}
  end

  @doc false
  @spec eth_get_filter_logs(list()) ::
          {:ok, [term()]} | {:error, integer(), String.t()}
  def eth_get_filter_logs([filter_id | _rest]) when is_binary(filter_id) do
    if filter_manager_available?() do
      case FilterManager.get_filter_logs(filter_id) do
        {:ok, logs} -> {:ok, logs}
        {:error, :not_found} -> {:error, -32000, "Filter not found"}
      end
    else
      {:error, -32603, "Filter manager not available"}
    end
  end

  def eth_get_filter_logs(_params) do
    {:error, -32602, "Invalid params: expected [filter_id]"}
  end

  @doc false
  @spec eth_uninstall_filter(list()) :: {:ok, boolean()}
  def eth_uninstall_filter([filter_id | _rest]) when is_binary(filter_id) do
    if filter_manager_available?() do
      {:ok, FilterManager.uninstall_filter(filter_id)}
    else
      {:ok, false}
    end
  end

  def eth_uninstall_filter(_params), do: {:ok, false}

  # -- Proof methods --------------------------------------------------------

  @doc false
  @spec eth_get_proof(list()) :: {:ok, map()} | {:error, integer(), String.t()}
  def eth_get_proof([address_hex, storage_keys, _block_tag | _rest])
      when is_binary(address_hex) and is_list(storage_keys) do
    with {:ok, address_bin} <- Hex.decode_data(address_hex) do
      account_data = fetch_account_for_proof(address_bin)

      storage_proofs =
        Enum.map(storage_keys, fn key_hex ->
          build_storage_proof(address_bin, key_hex)
        end)

      {:ok,
       %{
         "address" => Hex.encode_data(address_bin),
         "accountProof" => account_data.proof,
         "balance" => Hex.encode_quantity(account_data.balance),
         "codeHash" => Hex.encode_data(account_data.code_hash),
         "nonce" => Hex.encode_quantity(account_data.nonce),
         "storageHash" => Hex.encode_data(account_data.storage_root),
         "storageProof" => storage_proofs
       }}
    else
      _error ->
        {:error, -32602, "Invalid params: expected [address, keys, block]"}
    end
  end

  def eth_get_proof(_params) do
    {:error, -32602, "Invalid params: expected [address, storage_keys, block_tag]"}
  end

  # -- Fee & Gas methods (C2) -----------------------------------------------

  @doc false
  @spec eth_fee_history(list()) :: {:ok, map()} | {:error, integer(), String.t()}
  def eth_fee_history([block_count_hex, newest_block_hex | rest]) do
    reward_percentiles = List.first(rest) || []

    with {:ok, block_count} <- parse_quantity_or_int(block_count_hex),
         {:ok, newest} <- parse_block_or_tag(newest_block_hex) do
      if store_available?() do
        {_mod, name} = store()
        EthChain.FeeHistory.get_fee_history(block_count, newest, reward_percentiles, name)
      else
        {:ok,
         %{
           "oldestBlock" => "0x0",
           "baseFeePerGas" => ["0x0"],
           "gasUsedRatio" => [],
           "reward" => []
         }}
      end
    else
      _ -> {:error, -32602, "Invalid params"}
    end
  end

  def eth_fee_history(_params) do
    {:error, -32602, "Invalid params: expected [blockCount, newestBlock, rewardPercentiles]"}
  end

  @doc false
  @spec eth_max_priority_fee_per_gas(list()) :: {:ok, String.t()}
  def eth_max_priority_fee_per_gas(_params) do
    if store_available?() do
      {_mod, name} = store()

      case EthChain.GasOracle.suggest_max_priority_fee(name) do
        {:ok, fee} -> {:ok, Hex.encode_quantity(fee)}
        _ -> {:ok, "0x3b9aca00"}
      end
    else
      {:ok, "0x3b9aca00"}
    end
  end

  @doc false
  @spec eth_blob_base_fee(list()) :: {:ok, String.t()}
  def eth_blob_base_fee(_params) do
    case fetch_latest_header() do
      {:ok, header} when not is_nil(header) ->
        blob_fee = header.excess_blob_gas || 1
        {:ok, Hex.encode_quantity(blob_fee)}

      _ ->
        {:ok, "0x1"}
    end
  end

  @doc """
  Creates an EIP-2930 access list for the given transaction.

  Executes the transaction via the gas estimator to determine gas usage.
  Returns an empty access list with the estimated gas. Once the revm NIF
  supports access-list tracing, this will return the actual storage slots
  touched during execution.

  ## Parameters

    - `params` - A list where the first element is a call object map with
      keys `"from"`, `"to"`, `"data"`, `"value"`, `"gasPrice"`, etc.

  ## Returns

    - `{:ok, %{"accessList" => [...], "gasUsed" => "0x..."}}` on success.
    - `{:error, code, message}` on execution failure.
  """
  @spec eth_create_access_list(list()) ::
          {:ok, map()} | {:error, integer(), String.t()}
  def eth_create_access_list([call_obj | _rest]) when is_map(call_obj) do
    call_params = parse_call_params(call_obj)
    {_mod, store_name} = store()

    case EthVm.GasEstimator.estimate_gas(call_params, store_name) do
      {:ok, gas} ->
        # TODO: populate access list from revm execution trace once NIF supports it
        {:ok, %{"accessList" => [], "gasUsed" => Hex.encode_quantity(gas)}}

      {:error, :execution_reverted} ->
        {:error, 3, "execution reverted"}

      {:error, reason} ->
        {:error, -32603, "Internal error: #{inspect(reason)}"}
    end
  end

  def eth_create_access_list(_params) do
    {:ok, %{"accessList" => [], "gasUsed" => "0x5208"}}
  end

  @doc false
  @spec eth_send_transaction(list()) :: {:error, integer(), String.t()}
  def eth_send_transaction(_params) do
    {:error, -32601, "eth_sendTransaction is not supported (no key management)"}
  end

  # -- net_ namespace --------------------------------------------------------

  @doc false
  @spec net_version(list()) :: {:ok, String.t()}
  def net_version(_params) do
    network_id = Application.get_env(:eth_chain, :network_id, 1)
    {:ok, Integer.to_string(network_id)}
  end

  @doc false
  @spec net_listening(list()) :: {:ok, true}
  def net_listening(_params), do: {:ok, true}

  @doc false
  @spec net_peer_count(list()) :: {:ok, String.t()}
  def net_peer_count(_params) do
    count =
      try do
        apply(EthNet.Peer.Manager, :connected_count, [])
      catch
        :exit, _ -> 0
      end

    {:ok, Hex.encode_quantity(count)}
  end

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
  @spec engine_forkchoice_updated_v1(list()) :: {:ok, map()}
  def engine_forkchoice_updated_v1(params) do
    Engine.forkchoice_updated_v1(params)
  end

  @doc false
  @spec engine_forkchoice_updated_v2(list()) :: {:ok, map()}
  def engine_forkchoice_updated_v2(params) do
    Engine.forkchoice_updated_v2(params)
  end

  @doc false
  @spec engine_forkchoice_updated_v3(list()) :: {:ok, map()}
  def engine_forkchoice_updated_v3(params) do
    Engine.forkchoice_updated_v3(params)
  end

  @doc false
  @spec engine_forkchoice_updated_v4(list()) :: {:ok, map()}
  def engine_forkchoice_updated_v4(params) do
    Engine.forkchoice_updated_v4(params)
  end

  @doc false
  @spec engine_new_payload_v1(list()) :: {:ok, map()}
  def engine_new_payload_v1(params) do
    Engine.new_payload_v1(params)
  end

  @doc false
  @spec engine_new_payload_v2(list()) :: {:ok, map()}
  def engine_new_payload_v2(params) do
    Engine.new_payload_v2(params)
  end

  @doc false
  @spec engine_new_payload_v3(list()) :: {:ok, map()}
  def engine_new_payload_v3(params) do
    Engine.new_payload_v3(params)
  end

  @doc false
  @spec engine_new_payload_v4(list()) :: {:ok, map()}
  def engine_new_payload_v4(params) do
    Engine.new_payload_v4(params)
  end

  @doc false
  @spec engine_get_payload_v1(list()) :: rpc_result()
  def engine_get_payload_v1(params) do
    Engine.get_payload_v1(params)
  end

  @doc false
  @spec engine_get_payload_v2(list()) :: rpc_result()
  def engine_get_payload_v2(params) do
    Engine.get_payload_v2(params)
  end

  @doc false
  @spec engine_get_payload_v3(list()) :: rpc_result()
  def engine_get_payload_v3(params) do
    Engine.get_payload_v3(params)
  end

  @doc false
  @spec engine_get_payload_v4(list()) :: rpc_result()
  def engine_get_payload_v4(params) do
    Engine.get_payload_v4(params)
  end

  @doc false
  @spec engine_get_payload_bodies_by_hash_v1(list()) :: {:ok, list()}
  def engine_get_payload_bodies_by_hash_v1(params) do
    Engine.get_payload_bodies_by_hash_v1(params)
  end

  @doc false
  @spec engine_get_payload_bodies_by_hash_v2(list()) :: {:ok, list()}
  def engine_get_payload_bodies_by_hash_v2(params) do
    Engine.get_payload_bodies_by_hash_v2(params)
  end

  @doc false
  @spec engine_get_payload_bodies_by_range_v1(list()) :: {:ok, list()}
  def engine_get_payload_bodies_by_range_v1(params) do
    Engine.get_payload_bodies_by_range_v1(params)
  end

  @doc false
  @spec engine_get_payload_bodies_by_range_v2(list()) :: {:ok, list()}
  def engine_get_payload_bodies_by_range_v2(params) do
    Engine.get_payload_bodies_by_range_v2(params)
  end

  @doc false
  @spec engine_get_blobs_v1(list()) :: {:ok, list()}
  def engine_get_blobs_v1(params) do
    Engine.get_blobs_v1(params)
  end

  @doc false
  @spec engine_get_client_version_v1(list()) :: {:ok, list()}
  def engine_get_client_version_v1(params) do
    Engine.get_client_version_v1(params)
  end

  @doc false
  @spec engine_exchange_transition_config_v1(list()) :: {:ok, map()}
  def engine_exchange_transition_config_v1(params) do
    Engine.exchange_transition_config_v1(params)
  end

  @doc false
  @spec engine_exchange_capabilities(list()) :: {:ok, list()}
  def engine_exchange_capabilities(params) do
    Engine.exchange_capabilities(params)
  end

  # -- debug_ namespace ------------------------------------------------------

  def debug_get_raw_header(params), do: EthRpc.Debug.get_raw_header(params)
  def debug_get_raw_block(params), do: EthRpc.Debug.get_raw_block(params)
  def debug_get_raw_transaction(params), do: EthRpc.Debug.get_raw_transaction(params)
  def debug_get_raw_receipts(params), do: EthRpc.Debug.get_raw_receipts(params)

  # -- admin_ namespace ------------------------------------------------------

  def admin_node_info(params), do: EthRpc.Admin.node_info(params)
  def admin_peers(params), do: EthRpc.Admin.peers(params)
  def admin_add_peer(params), do: EthRpc.Admin.add_peer(params)
  def admin_set_log_level(params), do: EthRpc.Admin.set_log_level(params)

  # -- txpool_ namespace -----------------------------------------------------

  def txpool_content(params), do: EthRpc.Txpool.content(params)
  def txpool_status(params), do: EthRpc.Txpool.status(params)

  # -- Private helpers -------------------------------------------------------

  @spec parse_quantity_or_int(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp parse_quantity_or_int(val) when is_integer(val), do: {:ok, val}
  defp parse_quantity_or_int(val) when is_binary(val), do: Hex.decode_quantity(val)
  defp parse_quantity_or_int(_), do: {:error, :invalid_param}

  @spec parse_block_or_tag(String.t()) ::
          {:ok, non_neg_integer() | :latest} | {:error, term()}
  defp parse_block_or_tag("latest"), do: {:ok, :latest}
  defp parse_block_or_tag("earliest"), do: {:ok, 0}
  defp parse_block_or_tag("pending"), do: {:ok, :latest}
  defp parse_block_or_tag("0x" <> _ = hex), do: Hex.decode_quantity(hex)
  defp parse_block_or_tag(_), do: {:error, :invalid_block_tag}

  @spec fetch_latest_header() ::
          {:ok, EthCore.Types.BlockHeader.t() | nil} | {:error, term()}
  defp fetch_latest_header do
    if store_available?() do
      case store_call(:get_latest_block_number) do
        {:ok, nil} ->
          {:ok, nil}

        {:ok, number} ->
          case store_call(:get_block_by_number, [number]) do
            {:ok, {header_bin, _body_bin}} ->
              {:ok, :erlang.binary_to_term(header_bin)}

            _ ->
              {:ok, nil}
          end

        _ ->
          {:ok, nil}
      end
    else
      {:ok, nil}
    end
  end

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

  @spec sync_manager_available?() :: boolean()
  defp sync_manager_available? do
    pid = GenServer.whereis(EthNet.Sync.Manager)
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

  @spec parse_tx_index(list()) :: {:ok, non_neg_integer()} | {:error, :invalid_hex}
  defp parse_tx_index([_tag, index_hex | _rest]) when is_binary(index_hex) do
    Hex.decode_quantity(index_hex)
  end

  defp parse_tx_index(_), do: {:error, :invalid_hex}

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

  defp format_block_result({header_bin, body_bin}, full_txs) do
    header = :erlang.binary_to_term(header_bin)
    txs = decode_body_transactions(body_bin)
    {:ok, Formatters.format_block(header, txs, full_txs)}
  end

  @spec full_txs?(list()) :: boolean()
  defp full_txs?([_tag, true]), do: true
  defp full_txs?(_), do: false

  @spec filter_manager_available?() :: boolean()
  defp filter_manager_available? do
    pid = GenServer.whereis(EthRpc.FilterManager)
    is_pid(pid) and Process.alive?(pid)
  end

  @spec parse_log_filter(map()) :: LogQuery.filter()
  defp parse_log_filter(obj) do
    filter = %{}

    filter =
      case Map.get(obj, "fromBlock") do
        nil -> filter
        tag -> put_block_number(filter, :from_block, tag)
      end

    filter =
      case Map.get(obj, "toBlock") do
        nil -> filter
        tag -> put_block_number(filter, :to_block, tag)
      end

    filter =
      case Map.get(obj, "address") do
        nil ->
          filter

        addr when is_binary(addr) ->
          case Hex.decode_data(addr) do
            {:ok, bin} -> Map.put(filter, :address, bin)
            _ -> filter
          end

        addrs when is_list(addrs) ->
          decoded =
            Enum.flat_map(addrs, fn a ->
              case Hex.decode_data(a) do
                {:ok, bin} -> [bin]
                _ -> []
              end
            end)

          Map.put(filter, :address, decoded)
      end

    filter =
      case Map.get(obj, "topics") do
        nil ->
          filter

        topics when is_list(topics) ->
          decoded = Enum.map(topics, &decode_topic_filter/1)
          Map.put(filter, :topics, decoded)
      end

    case Map.get(obj, "blockHash") do
      nil ->
        filter

      hash_hex ->
        case Hex.decode_data(hash_hex) do
          {:ok, bin} -> Map.put(filter, :block_hash, bin)
          _ -> filter
        end
    end
  end

  @spec decode_topic_filter(term()) :: binary() | [binary()] | nil
  defp decode_topic_filter(nil), do: nil

  defp decode_topic_filter(topic) when is_binary(topic) do
    case Hex.decode_data(topic) do
      {:ok, bin} -> bin
      _ -> nil
    end
  end

  defp decode_topic_filter(topics) when is_list(topics) do
    Enum.flat_map(topics, fn t ->
      case Hex.decode_data(t) do
        {:ok, bin} -> [bin]
        _ -> []
      end
    end)
  end

  @spec put_block_number(map(), atom(), String.t()) :: map()
  defp put_block_number(filter, _key, "latest"), do: filter
  defp put_block_number(filter, key, "earliest"), do: Map.put(filter, key, 0)
  defp put_block_number(filter, _key, "pending"), do: filter

  defp put_block_number(filter, key, hex) when is_binary(hex) do
    case Hex.decode_quantity(hex) do
      {:ok, n} -> Map.put(filter, key, n)
      _ -> filter
    end
  end

  @spec decode_storage_slot(String.t()) :: {:ok, binary()} | {:error, term()}
  defp decode_storage_slot(hex) do
    case Hex.decode_data(hex) do
      {:ok, bin} -> {:ok, pad_to_32(bin)}
      error -> error
    end
  end

  @spec storage_key(binary(), binary()) :: binary()
  defp storage_key(address, slot) do
    EthCrypto.Hash.keccak256(address <> slot)
  end

  @spec pad_to_32(binary()) :: binary()
  defp pad_to_32(bin) when byte_size(bin) >= 32, do: binary_part(bin, 0, 32)

  defp pad_to_32(bin) do
    padding = 32 - byte_size(bin)
    <<0::size(padding * 8)>> <> bin
  end

  @spec fetch_account_for_proof(binary()) :: map()
  defp fetch_account_for_proof(address_bin) do
    empty_code = EthCore.Types.Account.empty_code_hash()
    empty_root = EthCore.Types.Account.empty_trie_root()

    case store_call(:get_account, [address_bin]) do
      {:ok, encoded} when is_binary(encoded) ->
        account = :erlang.binary_to_term(encoded)

        %{
          nonce: account.nonce,
          balance: account.balance,
          code_hash: account.code_hash,
          storage_root: account.storage_root,
          proof: []
        }

      _other ->
        %{
          nonce: 0,
          balance: 0,
          code_hash: empty_code,
          storage_root: empty_root,
          proof: []
        }
    end
  end

  @spec build_storage_proof(binary(), String.t()) :: map()
  defp build_storage_proof(address_bin, key_hex) do
    zero_value = "0x" <> String.duplicate("0", 64)

    case Hex.decode_data(key_hex) do
      {:ok, slot_bin} ->
        slot_padded = pad_to_32(slot_bin)
        skey = storage_key(address_bin, slot_padded)

        value =
          case store_call(:get_storage_trie_node, [skey]) do
            {:ok, nil} -> zero_value
            {:ok, v} when is_binary(v) -> Hex.encode_data(pad_to_32(v))
            _other -> zero_value
          end

        %{
          "key" => key_hex,
          "value" => value,
          "proof" => []
        }

      _error ->
        %{"key" => key_hex, "value" => zero_value, "proof" => []}
    end
  end

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

  @spec fetch_block_transactions(binary()) :: [SignedTransaction.t()]
  defp fetch_block_transactions(block_hash) do
    case store_call(:get_block_body, [block_hash]) do
      {:ok, nil} -> []
      {:ok, body_bin} -> decode_body_transactions(body_bin)
      _error -> []
    end
  end

  @spec decode_body_transactions(binary() | nil) :: [SignedTransaction.t()]
  defp decode_body_transactions(nil), do: []

  defp decode_body_transactions(body_bin) do
    body = :erlang.binary_to_term(body_bin)
    Map.get(body, :transactions, [])
  end

  @spec count_block_transactions({binary(), binary()} | nil) :: {:ok, String.t() | nil}
  defp count_block_transactions(nil), do: {:ok, nil}

  defp count_block_transactions({_header_bin, body_bin}) do
    txs = decode_body_transactions(body_bin)
    {:ok, Hex.encode_quantity(length(txs))}
  end

  @spec get_tx_at_index({binary(), binary()} | nil, non_neg_integer()) :: {:ok, map() | nil}
  defp get_tx_at_index(nil, _tx_index), do: {:ok, nil}

  defp get_tx_at_index({header_bin, body_bin}, tx_index) do
    header = :erlang.binary_to_term(header_bin)
    body = :erlang.binary_to_term(body_bin)

    case Enum.at(body.transactions, tx_index) do
      nil ->
        {:ok, nil}

      signed_tx ->
        block_hash = Formatters.compute_block_hash(header)

        {:ok,
         Formatters.format_transaction(signed_tx, %{
           block_hash: block_hash,
           block_number: header.number,
           tx_index: tx_index
         })}
    end
  end

  @spec lookup_tx_location(binary()) ::
          {:ok, {binary(), non_neg_integer()}} | {:error, term()}
  defp lookup_tx_location(tx_hash) do
    case store_call(:get_tx_location, [tx_hash]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, {_block_hash, _tx_index} = location} -> {:ok, location}
      error -> error
    end
  end

  @spec format_block_receipts({binary(), binary()} | nil) :: {:ok, list() | nil}
  defp format_block_receipts(nil), do: {:ok, nil}

  defp format_block_receipts({header_bin, body_bin}) do
    header = :erlang.binary_to_term(header_bin)
    body = :erlang.binary_to_term(body_bin)
    block_hash = Formatters.compute_block_hash(header)

    receipts =
      body.transactions
      |> Enum.with_index()
      |> Enum.map(fn {signed_tx, idx} ->
        tx_hash = SignedTransaction.tx_hash(signed_tx)

        case store_call(:get_receipt, [block_hash, idx]) do
          {:ok, nil} ->
            nil

          {:ok, receipt_bin} ->
            receipt = :erlang.binary_to_term(receipt_bin)

            Formatters.format_full_receipt(receipt, %{
              tx_hash: tx_hash,
              tx_index: idx,
              block_hash: block_hash,
              block_number: header.number,
              from: recover_tx_sender(signed_tx),
              to: tx_to_field(signed_tx),
              gas_used: receipt.cumulative_gas_used,
              contract_address: nil
            })

          _error ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, receipts}
  end

  @spec recover_tx_sender(SignedTransaction.t() | nil) :: binary() | nil
  defp recover_tx_sender(nil), do: nil

  defp recover_tx_sender(%SignedTransaction{} = signed_tx) do
    case EthCore.Transaction.Signer.recover_sender(signed_tx) do
      {:ok, address} -> address
      {:error, _} -> nil
    end
  end

  @spec tx_to_field(SignedTransaction.t() | nil) :: binary() | nil
  defp tx_to_field(nil), do: nil

  defp tx_to_field(%SignedTransaction{tx: tx}) do
    case tx do
      %Transaction.Legacy{to: to} -> to
      %Transaction.EIP2930{to: to} -> to
      %Transaction.EIP1559{to: to} -> to
      %Transaction.EIP4844{to: to} -> to
      %Transaction.EIP7702{to: to} -> to
    end
  end
end
