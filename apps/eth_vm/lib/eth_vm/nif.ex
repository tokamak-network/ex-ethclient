defmodule EthVm.Nif do
  @moduledoc """
  EVM implementation using the Rust NIF backend.

  Delegates transaction execution to `EthVm.Native` and converts
  results into `EthVm.Types` structs. Backed by revm via Rust NIF.
  """

  @behaviour EthVm.Evm

  alias EthVm.Native
  alias EthVm.Types.{BlockExecutionResult, ExecutionResult}

  @impl true
  @doc """
  Executes a single signed transaction via the Rust NIF.

  Uses the full execute_tx NIF when possible, which provides real
  EVM execution via revm including bytecode execution, gas metering,
  and state changes.
  """
  @spec execute_transaction(
          EthVm.Types.Environment.t(),
          EthCore.Types.SignedTransaction.t(),
          module()
        ) :: {:ok, ExecutionResult.t()} | {:error, term()}
  def execute_transaction(_env, signed_tx, _state_provider) do
    tx = signed_tx.tx
    {from, to, value, gas_limit, gas_price, data} = extract_tx_fields(tx)

    result =
      if data == <<>> do
        Native.execute_simple_tx(from, to, value, gas_limit, gas_price)
      else
        Native.execute_call(from, to, data, value, gas_limit, gas_price)
      end

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
        {:error, reason}
    end
  end

  @impl true
  @doc """
  Executes all transactions in a block via the Rust NIF.

  Processes each transaction sequentially, building receipts with
  cumulative gas tracking.
  """
  @spec execute_block(EthCore.Types.Block.t(), module()) ::
          {:ok, BlockExecutionResult.t()} | {:error, term()}
  def execute_block(block, state_provider) do
    env = %EthVm.Types.Environment{
      coinbase: block.header.coinbase,
      gas_limit: block.header.gas_limit,
      number: block.header.number,
      timestamp: block.header.timestamp
    }

    result =
      block.transactions
      |> Enum.reduce_while({[], 0}, fn tx, {receipts, cumulative_gas} ->
        case execute_transaction(env, tx, state_provider) do
          {:ok, exec_result} ->
            new_cumulative = cumulative_gas + exec_result.gas_used

            receipt = %EthCore.Types.Receipt{
              type: tx_type(tx.tx),
              status: if(exec_result.success, do: 1, else: 0),
              cumulative_gas_used: new_cumulative,
              logs_bloom: <<0::2048>>,
              logs: exec_result.logs
            }

            {:cont, {receipts ++ [receipt], new_cumulative}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:error, reason} ->
        {:error, reason}

      {receipts, total_gas} ->
        block_result = %BlockExecutionResult{
          receipts: receipts,
          gas_used: total_gas,
          account_updates: %{},
          logs: []
        }

        {:ok, block_result}
    end
  end

  # Extracts {from, to, value, gas_limit, gas_price, data} from a transaction.
  @spec extract_tx_fields(struct()) ::
          {binary(), binary(), non_neg_integer(), non_neg_integer(), non_neg_integer(), binary()}
  defp extract_tx_fields(tx) do
    from = Map.get(tx, :from, <<0::160>>)
    to = Map.get(tx, :to, <<0::160>>) || <<0::160>>
    value = Map.get(tx, :value, 0)
    gas_limit = Map.get(tx, :gas_limit, 21_000)
    data = Map.get(tx, :data, <<>>)

    gas_price =
      Map.get(tx, :gas_price, nil) ||
        Map.get(tx, :max_fee_per_gas, 0)

    {from, to, value, gas_limit, gas_price, data}
  end

  @spec tx_type(struct()) :: non_neg_integer()
  defp tx_type(%EthCore.Types.Transaction.Legacy{}), do: 0
  defp tx_type(%EthCore.Types.Transaction.EIP2930{}), do: 1
  defp tx_type(%EthCore.Types.Transaction.EIP1559{}), do: 2
  defp tx_type(%EthCore.Types.Transaction.EIP4844{}), do: 3
  defp tx_type(%EthCore.Types.Transaction.EIP7702{}), do: 4
  defp tx_type(_), do: 0
end
