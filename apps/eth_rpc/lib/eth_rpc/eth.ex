defmodule EthRpc.Eth do
  @moduledoc """
  Implements eth_, net_, and web3_ JSON-RPC namespace methods.

  Currently returns stub/placeholder values. Methods that require storage
  will be connected to the storage backend in a future phase.
  """

  alias EthRpc.Hex

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
    "web3_sha3" => :web3_sha3
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
  def eth_block_number(_params), do: {:ok, "0x0"}

  @doc false
  @spec eth_get_balance(list()) :: {:ok, String.t()}
  def eth_get_balance(_params), do: {:ok, "0x0"}

  @doc false
  @spec eth_get_transaction_count(list()) :: {:ok, String.t()}
  def eth_get_transaction_count(_params), do: {:ok, "0x0"}

  @doc false
  @spec eth_get_code(list()) :: {:ok, String.t()}
  def eth_get_code(_params), do: {:ok, "0x"}

  @doc false
  @spec eth_get_storage_at(list()) :: {:ok, String.t()}
  def eth_get_storage_at(_params) do
    {:ok, "0x" <> String.duplicate("0", 64)}
  end

  @doc false
  @spec eth_call(list()) :: {:ok, String.t()}
  def eth_call(_params), do: {:ok, "0x"}

  @doc false
  @spec eth_estimate_gas(list()) :: {:ok, String.t()}
  def eth_estimate_gas(_params), do: {:ok, "0x5208"}

  @doc false
  @spec eth_gas_price(list()) :: {:ok, String.t()}
  def eth_gas_price(_params), do: {:ok, "0x3B9ACA00"}

  @doc false
  @spec eth_get_block_by_number(list()) :: {:ok, nil}
  def eth_get_block_by_number(_params), do: {:ok, nil}

  @doc false
  @spec eth_get_block_by_hash(list()) :: {:ok, nil}
  def eth_get_block_by_hash(_params), do: {:ok, nil}

  @doc false
  @spec eth_get_transaction_by_hash(list()) :: {:ok, nil}
  def eth_get_transaction_by_hash(_params), do: {:ok, nil}

  @doc false
  @spec eth_get_transaction_receipt(list()) :: {:ok, nil}
  def eth_get_transaction_receipt(_params), do: {:ok, nil}

  @doc false
  @spec eth_send_raw_transaction(list()) :: {:error, integer(), String.t()}
  def eth_send_raw_transaction(_params) do
    {:error, -32603, "eth_sendRawTransaction not implemented yet"}
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

  # -- net_ namespace ----------------------------------------------------------

  @doc false
  @spec net_version(list()) :: {:ok, String.t()}
  def net_version(_params), do: {:ok, "1"}

  @doc false
  @spec net_listening(list()) :: {:ok, true}
  def net_listening(_params), do: {:ok, true}

  @doc false
  @spec net_peer_count(list()) :: {:ok, String.t()}
  def net_peer_count(_params), do: {:ok, "0x0"}

  # -- web3_ namespace ---------------------------------------------------------

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
end
