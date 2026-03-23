defmodule EthVm.GasEstimator do
  @moduledoc """
  Estimates gas required for transaction execution via binary search.

  Uses the EVM to execute transactions with varying gas limits,
  performing a binary search between the intrinsic gas cost and the
  block gas limit to find the minimum gas required for success.
  """

  alias EthVm.Constants
  alias EthVm.Types.{Environment, ExecutionResult}

  @default_block_gas_limit 30_000_000
  @max_iterations 64

  @doc """
  Estimates the gas required to execute a call.

  Performs a binary search between the intrinsic gas floor and the
  block gas limit. At each step, the transaction is executed via the
  configured EVM module. The search converges when `low >= high`.

  ## Parameters

    - `call_params` - Map with `:from`, `:to`, `:value`, `:data`,
      and optionally `:gas_price` or `:max_fee_per_gas`.
    - `store` - The store process (pid or registered name) for state lookups.
    - `opts` - Optional keyword list. Supported keys:
      - `:evm_module` - EVM implementation module (default: `EthVm.Mock`).
      - `:block_gas_limit` - Upper gas bound (default: 30,000,000).

  ## Returns

    - `{:ok, gas_estimate}` on success.
    - `{:error, reason}` if the transaction cannot succeed even at the
      block gas limit.
  """
  @spec estimate_gas(map(), pid() | atom(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas(call_params, store, opts \\ []) do
    evm_module = Keyword.get(opts, :evm_module, EthVm.Mock)
    block_gas_limit = Keyword.get(opts, :block_gas_limit, @default_block_gas_limit)

    low = intrinsic_gas(call_params)
    high = block_gas_limit

    # First, verify that execution succeeds at the upper bound
    case try_execute(call_params, high, evm_module, store) do
      {:ok, %ExecutionResult{success: true}} ->
        binary_search(call_params, low, high, evm_module, store, 0)

      {:ok, %ExecutionResult{success: false}} ->
        {:error, :execution_reverted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec binary_search(
          map(),
          non_neg_integer(),
          non_neg_integer(),
          module(),
          pid() | atom(),
          non_neg_integer()
        ) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp binary_search(_call_params, low, high, _evm_module, _store, iteration)
       when low >= high or iteration >= @max_iterations do
    {:ok, high}
  end

  defp binary_search(call_params, low, high, evm_module, store, iteration) do
    mid = div(low + high, 2)

    case try_execute(call_params, mid, evm_module, store) do
      {:ok, %ExecutionResult{success: true}} ->
        binary_search(call_params, low, mid, evm_module, store, iteration + 1)

      {:ok, %ExecutionResult{success: false}} ->
        binary_search(call_params, mid + 1, high, evm_module, store, iteration + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec try_execute(map(), non_neg_integer(), module(), pid() | atom()) ::
          {:ok, ExecutionResult.t()} | {:error, term()}
  defp try_execute(call_params, gas_limit, evm_module, store) do
    env = %Environment{
      coinbase: <<0::160>>,
      gas_limit: @default_block_gas_limit,
      number: 0,
      timestamp: System.system_time(:second)
    }

    tx = build_signed_tx(call_params, gas_limit)
    evm_module.execute_transaction(env, tx, store)
  end

  @spec build_signed_tx(map(), non_neg_integer()) :: EthCore.Types.SignedTransaction.t()
  defp build_signed_tx(call_params, gas_limit) do
    to = Map.get(call_params, :to, <<0::160>>)
    value = Map.get(call_params, :value, 0)
    data = Map.get(call_params, :data, <<>>)
    gas_price = Map.get(call_params, :gas_price, Map.get(call_params, :max_fee_per_gas, 0))

    tx = %EthCore.Types.Transaction.Legacy{
      nonce: 0,
      gas_price: gas_price,
      gas_limit: gas_limit,
      to: to,
      value: value,
      data: data
    }

    %EthCore.Types.SignedTransaction{tx: tx, v: 27, r: 0, s: 0}
  end

  @spec intrinsic_gas(map()) :: non_neg_integer()
  defp intrinsic_gas(call_params) do
    data = Map.get(call_params, :data, <<>>)
    to = Map.get(call_params, :to, nil)

    base =
      if is_nil(to) or to == <<>> do
        Constants.tx_create_gas_cost()
      else
        Constants.tx_gas_cost()
      end

    data_cost =
      data
      |> :binary.bin_to_list()
      |> Enum.reduce(0, fn byte, acc ->
        if byte == 0 do
          acc + Constants.tx_data_zero_gas_cost()
        else
          acc + Constants.tx_data_non_zero_gas_cost()
        end
      end)

    base + data_cost
  end
end
