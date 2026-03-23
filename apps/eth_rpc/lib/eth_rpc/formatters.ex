defmodule EthRpc.Formatters do
  @moduledoc """
  Formats internal types to JSON-RPC response maps.

  Converts block headers, accounts, transactions, and receipts from their
  internal struct representation to hex-encoded JSON-RPC response format.
  """

  alias EthCore.Types.{SignedTransaction, Transaction}
  alias EthRpc.Hex

  @doc """
  Formats a block header as a JSON-RPC block object.

  When `full_txs` is true, full transaction objects are included.
  When false, only transaction hashes are included.
  All integer values are hex-encoded per JSON-RPC spec.
  """
  @spec format_block(map(), boolean()) :: map()
  def format_block(header, full_txs) do
    format_block(header, [], full_txs)
  end

  @doc """
  Formats a block header with transactions as a JSON-RPC block object.

  When `full_txs` is true, full transaction objects are included.
  When false, only transaction hashes are included.
  """
  @spec format_block(map(), [SignedTransaction.t()], boolean()) :: map()
  def format_block(header, transactions, full_txs) do
    block_hash = compute_block_hash(header)

    base = %{
      "number" => Hex.encode_quantity(header.number),
      "hash" => encode_hash(block_hash),
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
      "transactions" => format_transactions(transactions, block_hash, header.number, full_txs),
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
  Formats a single signed transaction as a JSON-RPC transaction object.

  Includes all standard fields: hash, nonce, blockHash, blockNumber,
  transactionIndex, from, to, value, gas, gasPrice, input, v, r, s, type.
  """
  @spec format_transaction(SignedTransaction.t(), map()) :: map()
  def format_transaction(%SignedTransaction{} = signed_tx, opts) do
    tx = signed_tx.tx
    tx_hash = SignedTransaction.tx_hash(signed_tx)
    tx_type = Transaction.type(tx)

    from_address = recover_sender(signed_tx)

    base = %{
      "hash" => encode_hash(tx_hash),
      "nonce" => Hex.encode_quantity(tx_nonce(tx)),
      "blockHash" => encode_hash_or_nil(opts[:block_hash]),
      "blockNumber" => encode_quantity_or_nil(opts[:block_number]),
      "transactionIndex" => encode_quantity_or_nil(opts[:tx_index]),
      "from" => encode_address_or_nil(from_address),
      "to" => encode_address_or_nil(tx_to(tx)),
      "value" => Hex.encode_quantity(tx_value(tx)),
      "gas" => Hex.encode_quantity(tx_gas_limit(tx)),
      "input" => Hex.encode_data(tx_data(tx)),
      "v" => Hex.encode_quantity(signed_tx.v),
      "r" => Hex.encode_quantity(signed_tx.r),
      "s" => Hex.encode_quantity(signed_tx.s),
      "type" => Hex.encode_quantity(tx_type)
    }

    base
    |> put_gas_price_fields(tx, tx_type)
    |> put_access_list(tx, tx_type)
    |> put_blob_fields(tx, tx_type)
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

  @doc """
  Formats a full transaction receipt with block/tx context fields.
  """
  @spec format_full_receipt(map(), map()) :: map()
  def format_full_receipt(receipt, opts) do
    base = format_receipt(receipt)

    Map.merge(base, %{
      "transactionHash" => encode_hash_or_nil(opts[:tx_hash]),
      "transactionIndex" => encode_quantity_or_nil(opts[:tx_index]),
      "blockHash" => encode_hash_or_nil(opts[:block_hash]),
      "blockNumber" => encode_quantity_or_nil(opts[:block_number]),
      "from" => encode_address_or_nil(opts[:from]),
      "to" => encode_address_or_nil(opts[:to]),
      "gasUsed" => Hex.encode_quantity(opts[:gas_used] || 0),
      "contractAddress" => encode_address_or_nil(opts[:contract_address])
    })
  end

  @doc """
  Computes the block hash from a header struct.

  Uses RLP encoding + keccak256 via `EthStorage.Encoding.block_hash/1`.
  """
  @spec compute_block_hash(map()) :: binary()
  def compute_block_hash(header) do
    EthStorage.Encoding.block_hash(header)
  end

  # -- Private helpers ---------------------------------------------------------

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

  @spec encode_hash_or_nil(binary() | nil) :: String.t() | nil
  defp encode_hash_or_nil(nil), do: nil
  defp encode_hash_or_nil(hash), do: encode_hash(hash)

  @spec encode_address_or_nil(binary() | nil) :: String.t() | nil
  defp encode_address_or_nil(nil), do: nil
  defp encode_address_or_nil(addr), do: encode_address(addr)

  @spec encode_quantity_or_nil(non_neg_integer() | nil) :: String.t() | nil
  defp encode_quantity_or_nil(nil), do: nil
  defp encode_quantity_or_nil(n), do: Hex.encode_quantity(n)

  @spec format_transactions([SignedTransaction.t()], binary(), non_neg_integer(), boolean()) ::
          list()
  defp format_transactions([], _block_hash, _block_number, _full_txs), do: []

  defp format_transactions(txs, block_hash, block_number, true) do
    txs
    |> Enum.with_index()
    |> Enum.map(fn {signed_tx, idx} ->
      format_transaction(signed_tx, %{
        block_hash: block_hash,
        block_number: block_number,
        tx_index: idx
      })
    end)
  end

  defp format_transactions(txs, _block_hash, _block_number, false) do
    Enum.map(txs, fn signed_tx ->
      encode_hash(SignedTransaction.tx_hash(signed_tx))
    end)
  end

  @spec recover_sender(SignedTransaction.t()) :: binary() | nil
  defp recover_sender(signed_tx) do
    case EthCore.Transaction.Signer.recover_sender(signed_tx) do
      {:ok, address} -> address
      {:error, _} -> nil
    end
  end

  # Transaction field accessors that work across all tx types

  defp tx_nonce(%Transaction.Legacy{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP2930{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP1559{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP4844{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP7702{nonce: n}), do: n

  defp tx_to(%Transaction.Legacy{to: t}), do: t
  defp tx_to(%Transaction.EIP2930{to: t}), do: t
  defp tx_to(%Transaction.EIP1559{to: t}), do: t
  defp tx_to(%Transaction.EIP4844{to: t}), do: t
  defp tx_to(%Transaction.EIP7702{to: t}), do: t

  defp tx_value(%Transaction.Legacy{value: v}), do: v
  defp tx_value(%Transaction.EIP2930{value: v}), do: v
  defp tx_value(%Transaction.EIP1559{value: v}), do: v
  defp tx_value(%Transaction.EIP4844{value: v}), do: v
  defp tx_value(%Transaction.EIP7702{value: v}), do: v

  defp tx_gas_limit(%Transaction.Legacy{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP2930{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP1559{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP4844{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP7702{gas_limit: g}), do: g

  defp tx_data(%Transaction.Legacy{data: d}), do: d
  defp tx_data(%Transaction.EIP2930{data: d}), do: d
  defp tx_data(%Transaction.EIP1559{data: d}), do: d
  defp tx_data(%Transaction.EIP4844{data: d}), do: d
  defp tx_data(%Transaction.EIP7702{data: d}), do: d

  defp put_gas_price_fields(map, %Transaction.Legacy{gas_price: gp}, _type) do
    Map.put(map, "gasPrice", Hex.encode_quantity(gp))
  end

  defp put_gas_price_fields(map, %Transaction.EIP2930{gas_price: gp}, _type) do
    Map.put(map, "gasPrice", Hex.encode_quantity(gp))
  end

  defp put_gas_price_fields(map, tx, _type) do
    map
    |> Map.put("maxFeePerGas", Hex.encode_quantity(tx.max_fee_per_gas))
    |> Map.put("maxPriorityFeePerGas", Hex.encode_quantity(tx.max_priority_fee_per_gas))
  end

  defp put_access_list(map, _tx, 0), do: map

  defp put_access_list(map, tx, _type) do
    Map.put(map, "accessList", format_access_list(tx.access_list))
  end

  defp format_access_list(nil), do: []

  defp format_access_list(access_list) do
    Enum.map(access_list, fn {address, storage_keys} ->
      %{
        "address" => encode_address(address),
        "storageKeys" => Enum.map(storage_keys, &encode_hash/1)
      }
    end)
  end

  defp put_blob_fields(map, _tx, type) when type != 3, do: map

  defp put_blob_fields(map, tx, 3) do
    map
    |> Map.put("maxFeePerBlobGas", Hex.encode_quantity(tx.max_fee_per_blob_gas))
    |> Map.put("blobVersionedHashes", Enum.map(tx.blob_versioned_hashes, &encode_hash/1))
  end

  @spec maybe_put(map(), String.t(), term(), (term() -> term())) :: map()
  defp maybe_put(map, _key, nil, _formatter), do: map
  defp maybe_put(map, key, value, formatter), do: Map.put(map, key, formatter.(value))
end
