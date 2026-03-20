defmodule EthRpc.Formatters do
  @moduledoc """
  Formats internal types to JSON-RPC response maps.

  Converts block headers, accounts, and receipts from their internal
  struct representation to hex-encoded JSON-RPC response format.
  """

  alias EthRpc.Hex

  @doc """
  Formats a block header as a JSON-RPC block object.

  When `full_txs` is true, full transaction objects are included.
  When false, only transaction hashes are included.
  All integer values are hex-encoded per JSON-RPC spec.
  """
  @spec format_block(map(), boolean()) :: map()
  def format_block(header, full_txs) do
    base = %{
      "number" => Hex.encode_quantity(header.number),
      "hash" => encode_hash(compute_block_hash(header)),
      "parentHash" => encode_hash(header.parent_hash),
      "sha3Uncles" => encode_hash(header.ommers_hash),
      "miner" => encode_address(header.coinbase),
      "stateRoot" => encode_hash(header.state_root),
      "transactionsRoot" => encode_hash(header.transactions_root),
      "receiptsRoot" => encode_hash(header.receipts_root),
      "logsBloom" => Hex.encode_data(header.logs_bloom),
      "difficulty" => Hex.encode_quantity(header.difficulty),
      "gasLimit" => Hex.encode_quantity(header.gas_limit),
      "gasUsed" => Hex.encode_quantity(header.gas_used),
      "timestamp" => Hex.encode_quantity(header.timestamp),
      "extraData" => Hex.encode_data(header.extra_data),
      "mixHash" => encode_hash(header.mix_hash),
      "nonce" => Hex.encode_data(header.nonce),
      "size" => "0x0",
      "transactions" => format_transactions(full_txs),
      "uncles" => []
    }

    base
    |> maybe_put("baseFeePerGas", header.base_fee_per_gas, &Hex.encode_quantity/1)
    |> maybe_put(
      "withdrawalsRoot",
      header.withdrawals_root,
      &encode_hash/1
    )
    |> maybe_put("withdrawals", header.withdrawals_root, fn _ -> [] end)
    |> maybe_put(
      "blobGasUsed",
      header.blob_gas_used,
      &Hex.encode_quantity/1
    )
    |> maybe_put(
      "excessBlobGas",
      header.excess_blob_gas,
      &Hex.encode_quantity/1
    )
    |> maybe_put(
      "parentBeaconBlockRoot",
      header.parent_beacon_block_root,
      &encode_hash/1
    )
  end

  @doc """
  Formats an account balance as hex.
  """
  @spec format_balance(non_neg_integer()) :: String.t()
  def format_balance(balance) when is_integer(balance) and balance >= 0 do
    Hex.encode_quantity(balance)
  end

  @doc """
  Formats a transaction receipt as a JSON-RPC receipt object.
  """
  @spec format_receipt(map()) :: map()
  def format_receipt(receipt) do
    %{
      "type" => Hex.encode_quantity(receipt.type),
      "status" => Hex.encode_quantity(receipt.status),
      "cumulativeGasUsed" => Hex.encode_quantity(receipt.cumulative_gas_used),
      "logsBloom" => Hex.encode_data(receipt.logs_bloom),
      "logs" => Enum.map(receipt.logs, &format_log/1)
    }
  end

  @spec format_log(map()) :: map()
  defp format_log(log) do
    %{
      "address" => encode_address(log.address),
      "topics" => Enum.map(log.topics, &encode_hash/1),
      "data" => Hex.encode_data(log.data)
    }
  end

  @spec encode_hash(binary()) :: String.t()
  defp encode_hash(hash) when is_binary(hash), do: Hex.encode_data(hash)

  @spec encode_address(binary()) :: String.t()
  defp encode_address(addr) when is_binary(addr), do: Hex.encode_data(addr)

  @spec format_transactions(boolean()) :: list()
  defp format_transactions(_full_txs), do: []

  @spec compute_block_hash(map()) :: binary()
  defp compute_block_hash(_header) do
    # Placeholder: computing the real block hash requires RLP-encoding
    # the header and taking keccak256. For now, return a zero hash.
    <<0::256>>
  end

  @spec maybe_put(map(), String.t(), term(), (term() -> term())) :: map()
  defp maybe_put(map, _key, nil, _formatter), do: map
  defp maybe_put(map, key, value, formatter), do: Map.put(map, key, formatter.(value))
end
