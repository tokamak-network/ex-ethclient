defmodule EthRpc.PayloadParser do
  @moduledoc "Converts between Engine API execution payloads and internal types."

  alias EthCore.Types.{Block, BlockHeader, Withdrawal}
  alias EthRpc.Hex

  @doc """
  Parses a JSON execution payload map into a Block struct.

  Expects hex-encoded fields as per the Engine API spec.
  """
  @spec parse_execution_payload(map()) ::
          {:ok, Block.t()} | {:error, term()}
  def parse_execution_payload(payload) when is_map(payload) do
    with {:ok, header} <- parse_header(payload),
         {:ok, withdrawals} <- parse_withdrawals(payload) do
      transactions = parse_transactions(payload)

      {:ok,
       %Block{
         header: header,
         transactions: transactions,
         ommers: [],
         withdrawals: withdrawals
       }}
    end
  end

  def parse_execution_payload(_), do: {:error, :invalid_payload}

  @doc """
  Converts a Block to an execution payload map.

  All integer fields are hex-encoded per Engine API spec.
  """
  @spec to_execution_payload(Block.t(), <<_::256>>) :: map()
  def to_execution_payload(%Block{header: h} = block, block_hash) do
    base = %{
      "parentHash" => Hex.encode_data(h.parent_hash),
      "feeRecipient" => Hex.encode_data(h.coinbase),
      "stateRoot" => Hex.encode_data(h.state_root),
      "receiptsRoot" => Hex.encode_data(h.receipts_root),
      "logsBloom" => Hex.encode_data(h.logs_bloom),
      "prevRandao" => Hex.encode_data(h.mix_hash),
      "blockNumber" => Hex.encode_quantity(h.number),
      "gasLimit" => Hex.encode_quantity(h.gas_limit),
      "gasUsed" => Hex.encode_quantity(h.gas_used),
      "timestamp" => Hex.encode_quantity(h.timestamp),
      "extraData" => Hex.encode_data(h.extra_data),
      "baseFeePerGas" => encode_optional_quantity(h.base_fee_per_gas),
      "blockHash" => Hex.encode_data(block_hash),
      "transactions" => [],
      "withdrawals" => format_withdrawals(block.withdrawals),
      "blobGasUsed" => encode_optional_quantity(h.blob_gas_used),
      "excessBlobGas" => encode_optional_quantity(h.excess_blob_gas)
    }

    if h.parent_beacon_block_root do
      Map.put(
        base,
        "parentBeaconBlockRoot",
        Hex.encode_data(h.parent_beacon_block_root)
      )
    else
      base
    end
  end

  # --- Private ---

  @spec parse_transactions(map()) :: [binary()]
  defp parse_transactions(%{"transactions" => txs}) when is_list(txs) do
    Enum.flat_map(txs, fn
      hex when is_binary(hex) ->
        case Hex.decode_data(hex) do
          {:ok, raw} -> [raw]
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp parse_transactions(_), do: []

  @spec parse_header(map()) ::
          {:ok, BlockHeader.t()} | {:error, term()}
  defp parse_header(p) do
    with {:ok, parent_hash} <- decode_hash(p["parentHash"]),
         {:ok, coinbase} <- decode_address(p["feeRecipient"]),
         {:ok, state_root} <- decode_hash(p["stateRoot"]),
         {:ok, receipts_root} <- decode_hash(p["receiptsRoot"]),
         {:ok, logs_bloom} <- decode_data(p["logsBloom"]),
         {:ok, prev_randao} <- decode_hash(p["prevRandao"]),
         {:ok, number} <- decode_quantity(p["blockNumber"]),
         {:ok, gas_limit} <- decode_quantity(p["gasLimit"]),
         {:ok, gas_used} <- decode_quantity(p["gasUsed"]),
         {:ok, timestamp} <- decode_quantity(p["timestamp"]),
         {:ok, extra_data} <- decode_data(p["extraData"]),
         {:ok, base_fee} <- decode_optional_quantity(p["baseFeePerGas"]) do
      header = %BlockHeader{
        parent_hash: parent_hash,
        ommers_hash: empty_ommers_hash(),
        coinbase: coinbase,
        state_root: state_root,
        transactions_root: empty_root(),
        receipts_root: receipts_root,
        logs_bloom: logs_bloom,
        difficulty: 0,
        number: number,
        gas_limit: gas_limit,
        gas_used: gas_used,
        timestamp: timestamp,
        extra_data: extra_data,
        mix_hash: prev_randao,
        nonce: <<0::64>>,
        base_fee_per_gas: base_fee,
        blob_gas_used: decode_opt_qty(p["blobGasUsed"]),
        excess_blob_gas: decode_opt_qty(p["excessBlobGas"]),
        parent_beacon_block_root: decode_opt_hash(p["parentBeaconBlockRoot"])
      }

      {:ok, header}
    end
  end

  @spec parse_withdrawals(map()) ::
          {:ok, [Withdrawal.t()] | nil}
  defp parse_withdrawals(%{"withdrawals" => nil}), do: {:ok, nil}

  defp parse_withdrawals(%{"withdrawals" => ws}) when is_list(ws) do
    parsed =
      Enum.map(ws, fn w ->
        %Withdrawal{
          index: decode_qty_or_int(w["index"]),
          validator_index: decode_qty_or_int(w["validatorIndex"]),
          address: decode_addr_or_bin(w["address"]),
          amount: decode_qty_or_int(w["amount"])
        }
      end)

    {:ok, parsed}
  end

  defp parse_withdrawals(_), do: {:ok, nil}

  @spec format_withdrawals([Withdrawal.t()] | nil) :: list()
  defp format_withdrawals(nil), do: []

  defp format_withdrawals(ws) when is_list(ws) do
    Enum.map(ws, fn w ->
      %{
        "index" => Hex.encode_quantity(w.index),
        "validatorIndex" => Hex.encode_quantity(w.validator_index),
        "address" => Hex.encode_data(w.address),
        "amount" => Hex.encode_quantity(w.amount)
      }
    end)
  end

  @spec decode_hash(String.t() | nil) ::
          {:ok, <<_::256>>} | {:error, :invalid_hex}
  defp decode_hash(nil), do: {:error, :missing_field}

  defp decode_hash(hex) do
    case Hex.decode_data(hex) do
      {:ok, <<_::256>> = hash} -> {:ok, hash}
      {:ok, _} -> {:error, :invalid_hash_length}
      err -> err
    end
  end

  @spec decode_address(String.t() | nil) ::
          {:ok, <<_::160>>} | {:error, term()}
  defp decode_address(nil), do: {:error, :missing_field}

  defp decode_address(hex) do
    case Hex.decode_data(hex) do
      {:ok, <<_::160>> = addr} -> {:ok, addr}
      {:ok, _} -> {:error, :invalid_address_length}
      err -> err
    end
  end

  @spec decode_data(String.t() | nil) ::
          {:ok, binary()} | {:error, term()}
  defp decode_data(nil), do: {:ok, <<>>}
  defp decode_data(hex), do: Hex.decode_data(hex)

  @spec decode_quantity(String.t() | nil) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp decode_quantity(nil), do: {:error, :missing_field}
  defp decode_quantity(hex), do: Hex.decode_quantity(hex)

  @spec decode_optional_quantity(String.t() | nil) ::
          {:ok, non_neg_integer() | nil}
  defp decode_optional_quantity(nil), do: {:ok, nil}

  defp decode_optional_quantity(hex) do
    Hex.decode_quantity(hex)
  end

  @spec decode_opt_qty(String.t() | nil) :: non_neg_integer() | nil
  defp decode_opt_qty(nil), do: nil

  defp decode_opt_qty(hex) do
    case Hex.decode_quantity(hex) do
      {:ok, val} -> val
      _ -> nil
    end
  end

  @spec decode_opt_hash(String.t() | nil) :: binary() | nil
  defp decode_opt_hash(nil), do: nil

  defp decode_opt_hash(hex) do
    case Hex.decode_data(hex) do
      {:ok, <<_::256>> = h} -> h
      _ -> nil
    end
  end

  @spec decode_qty_or_int(String.t() | integer() | nil) ::
          non_neg_integer()
  defp decode_qty_or_int(val) when is_integer(val), do: val

  defp decode_qty_or_int(hex) when is_binary(hex) do
    case Hex.decode_quantity(hex) do
      {:ok, n} -> n
      _ -> 0
    end
  end

  defp decode_qty_or_int(_), do: 0

  @spec decode_addr_or_bin(String.t() | nil) :: binary()
  defp decode_addr_or_bin(nil), do: <<0::160>>

  defp decode_addr_or_bin(hex) do
    case Hex.decode_data(hex) do
      {:ok, bin} -> bin
      _ -> <<0::160>>
    end
  end

  @spec empty_ommers_hash() :: <<_::256>>
  defp empty_ommers_hash do
    # keccak256(RLP([])) — standard empty ommers hash
    EthCrypto.Hash.keccak256(<<0xC0>>)
  end

  @spec empty_root() :: <<_::256>>
  defp empty_root do
    # keccak256(RLP("")) — empty trie root
    EthCrypto.Hash.keccak256(<<0x80>>)
  end

  @spec encode_optional_quantity(non_neg_integer() | nil) ::
          String.t()
  defp encode_optional_quantity(nil), do: "0x0"
  defp encode_optional_quantity(n), do: Hex.encode_quantity(n)
end
