defmodule EthChain.Fork do
  @moduledoc """
  Fork configuration for Ethereum consensus rules.

  Determines the active fork at a given block number and timestamp, and
  provides convenience predicates for EIP feature gates.

  Uses mainnet fork block numbers and timestamps by default.
  """

  @type t ::
          :frontier
          | :homestead
          | :tangerine_whistle
          | :spurious_dragon
          | :byzantium
          | :constantinople
          | :petersburg
          | :istanbul
          | :muir_glacier
          | :berlin
          | :london
          | :arrow_glacier
          | :gray_glacier
          | :paris
          | :shanghai
          | :cancun
          | :prague

  # Mainnet fork activation blocks (block number based)
  @fork_blocks [
    {:prague, :timestamp, 1_740_434_112},
    {:cancun, :timestamp, 1_710_338_135},
    {:shanghai, :timestamp, 1_681_338_455},
    {:paris, :block, 15_537_394},
    {:gray_glacier, :block, 15_050_000},
    {:arrow_glacier, :block, 13_773_000},
    {:london, :block, 12_965_000},
    {:berlin, :block, 12_244_000},
    {:muir_glacier, :block, 9_200_000},
    {:istanbul, :block, 9_069_000},
    {:petersburg, :block, 7_280_000},
    {:constantinople, :block, 7_280_000},
    {:byzantium, :block, 4_370_000},
    {:spurious_dragon, :block, 2_675_000},
    {:tangerine_whistle, :block, 2_463_000},
    {:homestead, :block, 1_150_000},
    {:frontier, :block, 0}
  ]

  @doc """
  Determines the active fork at a given block number and timestamp.

  Checks timestamp-based forks first (Shanghai+), then block-number-based forks.
  """
  @spec active_fork(block_number :: non_neg_integer(), timestamp :: non_neg_integer()) :: t()
  def active_fork(block_number, timestamp) do
    Enum.find_value(@fork_blocks, :frontier, fn
      {fork, :timestamp, activation_ts} ->
        if timestamp >= activation_ts, do: fork

      {fork, :block, activation_block} ->
        if block_number >= activation_block, do: fork
    end)
  end

  @doc "Returns true if the fork supports EIP-1559 (London and later)."
  @spec eip1559?(t()) :: boolean()
  def eip1559?(fork), do: fork_index(fork) >= fork_index(:london)

  @doc "Returns true if the fork supports withdrawals (Shanghai and later)."
  @spec withdrawals?(t()) :: boolean()
  def withdrawals?(fork), do: fork_index(fork) >= fork_index(:shanghai)

  @doc "Returns true if the fork supports blob transactions (Cancun and later)."
  @spec blob_transactions?(t()) :: boolean()
  def blob_transactions?(fork), do: fork_index(fork) >= fork_index(:cancun)

  # Ordered fork indices for comparison
  @fork_order [
    :frontier,
    :homestead,
    :tangerine_whistle,
    :spurious_dragon,
    :byzantium,
    :constantinople,
    :petersburg,
    :istanbul,
    :muir_glacier,
    :berlin,
    :london,
    :arrow_glacier,
    :gray_glacier,
    :paris,
    :shanghai,
    :cancun,
    :prague
  ]

  defp fork_index(fork) do
    Enum.find_index(@fork_order, &(&1 == fork)) || 0
  end
end
