defmodule EthChain.FeeHistory do
  @moduledoc """
  Computes fee history for a range of blocks per EIP-1559.

  Returns base fee, gas usage ratios, and reward percentiles for a
  contiguous range of blocks, as required by the `eth_feeHistory` RPC method.
  """

  alias EthChain.BaseFee
  alias EthStorage.{BlockStore, Store}

  @doc """
  Returns fee history for a range of blocks.

  ## Parameters

    - `block_count` - Number of blocks to include (capped at 1024)
    - `newest_block` - The newest block number, or `:latest`
    - `reward_percentiles` - Sorted list of percentile values (0-100)
    - `store` - The storage server to query

  ## Returns

    `{:ok, map}` where the map contains:
    - `"oldestBlock"` - hex-encoded oldest block number
    - `"baseFeePerGas"` - list of hex-encoded base fees (block_count + 1 entries)
    - `"gasUsedRatio"` - list of gas used ratios (floats, block_count entries)
    - `"reward"` - list of per-block, per-percentile reward values (hex-encoded)
  """
  @spec get_fee_history(
          non_neg_integer(),
          non_neg_integer() | :latest,
          [float()],
          GenServer.server()
        ) :: {:ok, map()} | {:error, term()}
  def get_fee_history(block_count, newest_block, reward_percentiles, store \\ Store) do
    block_count = min(block_count, 1024)

    with {:ok, newest_num} <- resolve_block_number(newest_block, store) do
      oldest = max(0, newest_num - block_count + 1)
      actual_count = newest_num - oldest + 1

      {base_fees, gas_ratios, rewards} =
        Enum.reduce(oldest..newest_num, {[], [], []}, fn num, {bf_acc, gr_acc, rw_acc} ->
          case BlockStore.get_block_by_number(num, store) do
            {:ok, %{header: header, transactions: txs}} ->
              base_fee = header.base_fee_per_gas || 0
              ratio = gas_used_ratio(header.gas_used, header.gas_limit)
              block_rewards = compute_rewards(txs, base_fee, reward_percentiles)
              {bf_acc ++ [base_fee], gr_acc ++ [ratio], rw_acc ++ [block_rewards]}

            _ ->
              {bf_acc ++ [0], gr_acc ++ [0.0],
               rw_acc ++ [Enum.map(reward_percentiles, fn _ -> 0 end)]}
          end
        end)

      # Add one extra base fee entry for the next block
      next_base_fee = compute_next_base_fee(newest_num, store)
      all_base_fees = base_fees ++ [next_base_fee]

      result = %{
        "oldestBlock" => encode_hex(oldest),
        "baseFeePerGas" => Enum.map(all_base_fees, &encode_hex/1),
        "gasUsedRatio" => gas_ratios,
        "reward" => Enum.map(rewards, fn r -> Enum.map(r, &encode_hex/1) end)
      }

      # Sanity check: baseFeePerGas should have actual_count + 1 entries
      ^actual_count = length(gas_ratios)

      {:ok, result}
    end
  end

  # -- Private helpers -------------------------------------------------------

  @spec resolve_block_number(:latest | non_neg_integer(), GenServer.server()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp resolve_block_number(:latest, store) do
    case BlockStore.latest_block_number(store) do
      {:ok, nil} -> {:ok, 0}
      {:ok, n} -> {:ok, n}
      error -> error
    end
  end

  defp resolve_block_number(n, _store) when is_integer(n), do: {:ok, n}

  @spec gas_used_ratio(non_neg_integer(), non_neg_integer()) :: float()
  defp gas_used_ratio(_gas_used, 0), do: 0.0
  defp gas_used_ratio(gas_used, gas_limit), do: gas_used / gas_limit

  @spec compute_rewards(
          [EthCore.Types.SignedTransaction.t()],
          non_neg_integer(),
          [float()]
        ) :: [non_neg_integer()]
  defp compute_rewards(txs, base_fee, percentiles) when is_list(txs) do
    if txs == [] do
      Enum.map(percentiles, fn _ -> 0 end)
    else
      priority_fees =
        txs
        |> Enum.map(&tx_priority_fee(&1, base_fee))
        |> Enum.sort()

      Enum.map(percentiles, fn pct ->
        idx = div(length(priority_fees) * trunc(pct), 100)
        idx = min(idx, length(priority_fees) - 1)
        Enum.at(priority_fees, max(idx, 0))
      end)
    end
  end

  defp compute_rewards(_txs, _base_fee, percentiles) do
    Enum.map(percentiles, fn _ -> 0 end)
  end

  @spec tx_priority_fee(EthCore.Types.SignedTransaction.t(), non_neg_integer()) ::
          non_neg_integer()
  defp tx_priority_fee(%{tx: %EthCore.Types.Transaction.Legacy{gas_price: gp}}, base_fee) do
    max(gp - base_fee, 0)
  end

  defp tx_priority_fee(%{tx: %EthCore.Types.Transaction.EIP2930{gas_price: gp}}, base_fee) do
    max(gp - base_fee, 0)
  end

  defp tx_priority_fee(%{tx: %{max_priority_fee_per_gas: mpf}}, _base_fee), do: mpf

  @spec compute_next_base_fee(non_neg_integer(), GenServer.server()) :: non_neg_integer()
  defp compute_next_base_fee(block_number, store) do
    case BlockStore.get_block_by_number(block_number, store) do
      {:ok, %{header: header}} ->
        parent_base_fee = header.base_fee_per_gas || 0

        BaseFee.calc_next_base_fee(
          header.gas_used,
          header.gas_limit,
          parent_base_fee
        )

      _ ->
        0
    end
  end

  @spec encode_hex(non_neg_integer()) :: String.t()
  defp encode_hex(0), do: "0x0"

  defp encode_hex(n) when is_integer(n) and n > 0 do
    ("0x" <> Integer.to_string(n, 16)) |> String.downcase()
  end
end
