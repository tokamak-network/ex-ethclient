defmodule EthChain.GasOracle do
  @moduledoc """
  Estimates gas price from recent block history.

  Looks at the last N blocks and collects effective gas prices from transactions
  to produce a median-based estimate. Falls back to 1 gwei when no data is available.
  """

  alias EthStorage.{BlockStore, Store}

  @default_block_count 20
  @fallback_gas_price 1_000_000_000
  @fallback_priority_fee 1_000_000_000

  @doc """
  Suggests a gas price based on recent block transaction history.

  Examines the last 20 blocks for effective gas prices and returns a
  median-based estimate. Falls back to 1 gwei (1_000_000_000 wei) if
  no blocks or transactions are available.
  """
  @spec suggest_gas_price(GenServer.server()) :: {:ok, non_neg_integer()}
  def suggest_gas_price(store \\ Store) do
    prices = collect_gas_prices(store, @default_block_count)

    if prices == [] do
      {:ok, @fallback_gas_price}
    else
      {:ok, percentile(prices, 60)}
    end
  end

  @doc """
  Suggests a max priority fee per gas based on recent block history.

  Examines the last 20 blocks for priority fees and returns a median-based
  estimate. Falls back to 1 gwei (1_000_000_000 wei) if no data is available.
  """
  @spec suggest_max_priority_fee(GenServer.server()) :: {:ok, non_neg_integer()}
  def suggest_max_priority_fee(store \\ Store) do
    fees = collect_priority_fees(store, @default_block_count)

    if fees == [] do
      {:ok, @fallback_priority_fee}
    else
      {:ok, percentile(fees, 60)}
    end
  end

  # -- Private helpers -------------------------------------------------------

  @spec collect_gas_prices(GenServer.server(), non_neg_integer()) ::
          [non_neg_integer()]
  defp collect_gas_prices(store, block_count) do
    case BlockStore.latest_block_number(store) do
      {:ok, nil} ->
        []

      {:ok, latest} ->
        first = max(0, latest - block_count + 1)

        first..latest
        |> Enum.flat_map(fn num ->
          case BlockStore.get_block_by_number(num, store) do
            {:ok, %{transactions: txs}} when is_list(txs) ->
              Enum.map(txs, &effective_gas_price/1)

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  @spec collect_priority_fees(GenServer.server(), non_neg_integer()) ::
          [non_neg_integer()]
  defp collect_priority_fees(store, block_count) do
    case BlockStore.latest_block_number(store) do
      {:ok, nil} ->
        []

      {:ok, latest} ->
        first = max(0, latest - block_count + 1)

        first..latest
        |> Enum.flat_map(fn num ->
          case BlockStore.get_block_by_number(num, store) do
            {:ok, %{header: header, transactions: txs}} when is_list(txs) ->
              base_fee = header.base_fee_per_gas || 0
              Enum.map(txs, &priority_fee(&1, base_fee))

            _ ->
              []
          end
        end)

      _ ->
        []
    end
  end

  @spec effective_gas_price(EthCore.Types.SignedTransaction.t()) :: non_neg_integer()
  defp effective_gas_price(%{tx: %EthCore.Types.Transaction.Legacy{gas_price: gp}}), do: gp
  defp effective_gas_price(%{tx: %EthCore.Types.Transaction.EIP2930{gas_price: gp}}), do: gp

  defp effective_gas_price(%{tx: %EthCore.Types.Transaction.EIP1559{max_fee_per_gas: mf}}),
    do: mf

  defp effective_gas_price(%{tx: %EthCore.Types.Transaction.EIP4844{max_fee_per_gas: mf}}),
    do: mf

  defp effective_gas_price(%{tx: %EthCore.Types.Transaction.EIP7702{max_fee_per_gas: mf}}),
    do: mf

  @spec priority_fee(EthCore.Types.SignedTransaction.t(), non_neg_integer()) ::
          non_neg_integer()
  defp priority_fee(%{tx: %EthCore.Types.Transaction.Legacy{gas_price: gp}}, base_fee) do
    max(gp - base_fee, 0)
  end

  defp priority_fee(%{tx: %EthCore.Types.Transaction.EIP2930{gas_price: gp}}, base_fee) do
    max(gp - base_fee, 0)
  end

  defp priority_fee(%{tx: %{max_priority_fee_per_gas: mpf}}, _base_fee), do: mpf

  @spec percentile([non_neg_integer()], non_neg_integer()) :: non_neg_integer()
  defp percentile(sorted_list, pct) do
    sorted = Enum.sort(sorted_list)
    idx = div(length(sorted) * pct, 100)
    idx = min(idx, length(sorted) - 1)
    Enum.at(sorted, idx)
  end
end
