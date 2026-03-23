defmodule EthVm.CallExecutor do
  @moduledoc """
  Executes eth_call (read-only contract calls) via the EVM.

  Simulates a transaction execution without committing state changes.
  Used by the `eth_call` JSON-RPC method to query contract state.
  """

  alias EthVm.Types.{Environment, ExecutionResult}

  @default_block_gas_limit 30_000_000

  @doc """
  Executes a read-only call against the current state.

  Builds a transaction from `call_params`, executes it with the
  block gas limit, and returns the output bytes. State changes are
  discarded.

  ## Parameters

    - `call_params` - Map with `:from`, `:to`, `:value`, `:data`,
      and optionally `:gas_price` or `:max_fee_per_gas`.
    - `store` - The store process (pid or registered name) for state lookups.
    - `opts` - Optional keyword list. Supported keys:
      - `:evm_module` - EVM implementation module (default: `EthVm.Mock`).
      - `:block_gas_limit` - Gas limit for the call (default: 30,000,000).

  ## Returns

    - `{:ok, output_bytes}` on success, where `output_bytes` is the
      raw binary output from the EVM.
    - `{:error, reason}` if execution fails or reverts.
  """
  @spec execute_call(map(), pid() | atom(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def execute_call(call_params, store, opts \\ []) do
    evm_module = Keyword.get(opts, :evm_module, EthVm.Mock)
    block_gas_limit = Keyword.get(opts, :block_gas_limit, @default_block_gas_limit)

    env = %Environment{
      coinbase: <<0::160>>,
      gas_limit: block_gas_limit,
      number: 0,
      timestamp: System.system_time(:second)
    }

    tx = build_call_tx(call_params, block_gas_limit)

    case evm_module.execute_transaction(env, tx, store) do
      {:ok, %ExecutionResult{success: true, output: output}} ->
        {:ok, output}

      {:ok, %ExecutionResult{success: false}} ->
        {:error, :execution_reverted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec build_call_tx(map(), non_neg_integer()) :: EthCore.Types.SignedTransaction.t()
  defp build_call_tx(call_params, gas_limit) do
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
end
