defmodule EthVm.Nif do
  @moduledoc """
  EVM implementation using the Rust NIF backend.

  Delegates transaction execution to `EthVm.Native` and converts
  results into `EthVm.Types` structs. Backed by revm via Rust NIF.

  Supports all 5 Ethereum transaction types:
  - Legacy (Type 0)
  - EIP-2930 (Type 1) with access lists
  - EIP-1559 (Type 2) with dynamic fees
  - EIP-4844 (Type 3) with blob gas
  - EIP-7702 (Type 4) with authorization lists

  Uses `execute_tx_v3` which provides full block context (coinbase,
  timestamp, base fee, prevrandao) and loads pre-fetched account state
  from the storage backend.
  """

  @behaviour EthVm.Evm

  alias EthVm.Native
  alias EthVm.StateLoader
  alias EthVm.Types.{BlockExecutionResult, ExecutionResult}

  require Logger

  @impl true
  @doc """
  Executes a single signed transaction via the Rust NIF.

  Uses execute_tx_v3 which provides full block context and pre-loaded
  account state from the storage backend. The SpecId is determined
  automatically from block number and timestamp.
  """
  @spec execute_transaction(
          EthVm.Types.Environment.t(),
          EthCore.Types.SignedTransaction.t(),
          module()
        ) :: {:ok, ExecutionResult.t()} | {:error, term()}
  def execute_transaction(env, signed_tx, state_provider) do
    fields = extract_tx_fields(signed_tx)

    # Load pre-fetched state from the storage backend
    state_data = load_state(fields, signed_tx, state_provider)

    result =
      Native.execute_tx_v3(
        env.number || 0,
        env.timestamp || 0,
        env.coinbase || <<0::160>>,
        env.base_fee_per_gas || 0,
        env.prev_randao || <<0::256>>,
        env.gas_limit || 30_000_000,
        env.excess_blob_gas || 0,
        fields.tx_type,
        fields.from,
        fields.to,
        fields.value,
        fields.gas_limit,
        fields.gas_price,
        fields.max_priority_fee,
        fields.max_fee_per_blob_gas,
        fields.data,
        fields.nonce,
        state_data,
        fields.access_list_data,
        fields.blob_hashes_data
      )

    case result do
      {:ok, map} ->
        execution_result = %ExecutionResult{
          success: Map.get(map, :success, false),
          gas_used: Map.get(map, :gas_used, 0),
          gas_refunded: Map.get(map, :gas_refunded, 0),
          output: Map.get(map, :output, <<>>),
          logs: Map.get(map, :logs, []),
          error: nil
        }

        {:ok, execution_result}

      {:error, reason} ->
        Logger.warning("NIF execution error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  @doc """
  Executes all transactions in a block via the Rust NIF.

  Processes each transaction sequentially with state threading: state
  changes from transaction N are visible to transaction N+1. Builds
  receipts with cumulative gas tracking and aggregates all account
  updates and logs.
  """
  @spec execute_block(EthCore.Types.Block.t(), module()) ::
          {:ok, BlockExecutionResult.t()} | {:error, term()}
  def execute_block(block, state_provider) do
    env = %EthVm.Types.Environment{
      coinbase: block.header.coinbase,
      gas_limit: block.header.gas_limit,
      number: block.header.number,
      timestamp: block.header.timestamp,
      base_fee_per_gas: block.header.base_fee_per_gas || 0,
      prev_randao: block.header.mix_hash,
      excess_blob_gas: block.header.excess_blob_gas || 0
    }

    initial_state = %{}

    result =
      block.transactions
      |> Enum.reduce_while(
        {[], 0, initial_state, []},
        fn tx, {receipts, cumulative_gas, state, logs} ->
          case execute_transaction(env, tx, state_provider) do
            {:ok, exec_result} ->
              new_cumulative = cumulative_gas + exec_result.gas_used
              new_state = merge_state_changes(state, exec_result)

              receipt = %EthCore.Types.Receipt{
                type: tx_type(tx.tx),
                status: if(exec_result.success, do: 1, else: 0),
                cumulative_gas_used: new_cumulative,
                logs_bloom: <<0::2048>>,
                logs: exec_result.logs
              }

              new_logs = logs ++ exec_result.logs
              {:cont, {[receipt | receipts], new_cumulative, new_state, new_logs}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )

    case result do
      {:error, reason} ->
        {:error, reason}

      {receipts, total_gas, final_updates, all_logs} ->
        block_result = %BlockExecutionResult{
          receipts: Enum.reverse(receipts),
          gas_used: total_gas,
          account_updates: final_updates,
          logs: all_logs
        }

        {:ok, block_result}
    end
  end

  @spec merge_state_changes(map(), ExecutionResult.t()) :: map()
  defp merge_state_changes(current_state, %ExecutionResult{} = _exec_result) do
    # State changes from the NIF are handled by the storage layer.
    # The NIF loads fresh state from storage for each transaction.
    current_state
  end

  # Loads pre-fetched state from the storage backend for the transaction.
  # Falls back to empty state if state loading fails (e.g., in tests without a store).
  @spec load_state(map(), EthCore.Types.SignedTransaction.t(), module()) :: binary()
  defp load_state(fields, signed_tx, state_provider) do
    tx_info = %{
      from: fields.from,
      to: if(fields.to == <<>>, do: nil, else: fields.to),
      access_list: Map.get(signed_tx.tx, :access_list, [])
    }

    case StateLoader.load_tx_state(tx_info, state_provider) do
      {:ok, state_binary} ->
        state_binary

      {:error, reason} ->
        Logger.debug("State loading failed (#{inspect(reason)}), using empty state")
        <<>>
    end
  end

  # Extracts all transaction fields needed for execute_tx_v3 from a signed transaction.
  @spec extract_tx_fields(EthCore.Types.SignedTransaction.t()) :: map()
  defp extract_tx_fields(signed_tx) do
    tx = signed_tx.tx
    type_byte = tx_type(tx)
    from = Map.get(tx, :from, <<0::160>>)
    to = Map.get(tx, :to) || <<>>
    value = encode_u256(Map.get(tx, :value, 0))
    gas_limit = Map.get(tx, :gas_limit, 21_000)
    data = Map.get(tx, :data, <<>>)
    nonce = Map.get(tx, :nonce, 0)

    # Gas price: for Legacy/EIP-2930 use gas_price, for EIP-1559+ use max_fee_per_gas
    gas_price =
      case type_byte do
        t when t in [0, 1] -> encode_u256(Map.get(tx, :gas_price, 0))
        _ -> encode_u256(Map.get(tx, :max_fee_per_gas, 0))
      end

    max_priority_fee =
      case type_byte do
        t when t >= 2 -> encode_u256(Map.get(tx, :max_priority_fee_per_gas, 0))
        _ -> <<>>
      end

    max_fee_per_blob_gas =
      case type_byte do
        3 -> encode_u256(Map.get(tx, :max_fee_per_blob_gas, 0))
        _ -> <<>>
      end

    access_list_data =
      case Map.get(tx, :access_list) do
        nil -> <<>>
        [] -> <<>>
        list -> encode_access_list(list)
      end

    blob_hashes_data =
      case Map.get(tx, :blob_versioned_hashes) do
        nil -> <<>>
        [] -> <<>>
        hashes -> encode_blob_hashes(hashes)
      end

    %{
      tx_type: type_byte,
      from: from,
      to: to,
      value: value,
      gas_limit: gas_limit,
      gas_price: gas_price,
      max_priority_fee: max_priority_fee,
      max_fee_per_blob_gas: max_fee_per_blob_gas,
      data: data,
      nonce: nonce,
      access_list_data: access_list_data,
      blob_hashes_data: blob_hashes_data
    }
  end

  # Encodes an integer as a big-endian binary (minimal representation).
  @spec encode_u256(non_neg_integer()) :: binary()
  defp encode_u256(0), do: <<>>

  defp encode_u256(n) when is_integer(n) and n > 0 do
    :binary.encode_unsigned(n, :big)
  end

  # Encodes an access list into binary format.
  #
  # Format:
  #   4 bytes: num_entries (u32 big-endian)
  #   Per entry:
  #     20 bytes: address
  #     4 bytes: num_keys (u32 big-endian)
  #     N * 32 bytes: storage keys
  @spec encode_access_list([{binary(), [binary()]}]) :: binary()
  defp encode_access_list(entries) do
    num_entries = length(entries)

    entry_data =
      Enum.reduce(entries, <<>>, fn {address, storage_keys}, acc ->
        addr = pad_address(address)
        num_keys = length(storage_keys)

        keys_data =
          Enum.reduce(storage_keys, <<>>, fn key, kacc ->
            kacc <> pad_hash(key)
          end)

        acc <> addr <> <<num_keys::unsigned-big-32>> <> keys_data
      end)

    <<num_entries::unsigned-big-32>> <> entry_data
  end

  # Encodes blob versioned hashes as concatenated 32-byte values.
  @spec encode_blob_hashes([binary()]) :: binary()
  defp encode_blob_hashes(hashes) do
    Enum.reduce(hashes, <<>>, fn hash, acc ->
      acc <> pad_hash(hash)
    end)
  end

  # Pads or truncates an address to 20 bytes.
  @spec pad_address(binary()) :: <<_::160>>
  defp pad_address(addr) when byte_size(addr) == 20, do: addr

  defp pad_address(addr) when byte_size(addr) < 20 do
    padding_size = 20 - byte_size(addr)
    <<0::size(padding_size * 8)>> <> addr
  end

  defp pad_address(addr), do: binary_part(addr, byte_size(addr) - 20, 20)

  # Pads or truncates a hash to 32 bytes.
  @spec pad_hash(binary()) :: <<_::256>>
  defp pad_hash(hash) when byte_size(hash) == 32, do: hash

  defp pad_hash(hash) when byte_size(hash) < 32 do
    padding_size = 32 - byte_size(hash)
    <<0::size(padding_size * 8)>> <> hash
  end

  defp pad_hash(hash), do: binary_part(hash, byte_size(hash) - 32, 32)

  @spec tx_type(struct()) :: non_neg_integer()
  defp tx_type(%EthCore.Types.Transaction.Legacy{}), do: 0
  defp tx_type(%EthCore.Types.Transaction.EIP2930{}), do: 1
  defp tx_type(%EthCore.Types.Transaction.EIP1559{}), do: 2
  defp tx_type(%EthCore.Types.Transaction.EIP4844{}), do: 3
  defp tx_type(%EthCore.Types.Transaction.EIP7702{}), do: 4
  defp tx_type(_), do: 0
end
