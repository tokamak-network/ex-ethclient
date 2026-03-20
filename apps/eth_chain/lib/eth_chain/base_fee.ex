defmodule EthChain.BaseFee do
  @moduledoc """
  EIP-1559 base fee calculation.

  Computes the expected base fee for the next block based on the parent
  block's gas usage relative to its target (gas_limit / elasticity_multiplier).
  """

  @elasticity_multiplier 2
  @base_fee_change_denominator 8

  @doc """
  Calculates the expected base fee for the next block.

  - If parent gas_used == target: base fee stays the same
  - If parent gas_used > target: base fee increases proportionally
  - If parent gas_used < target: base fee decreases proportionally (min 0)

  Target is defined as `parent_gas_limit / elasticity_multiplier`.
  """
  @spec calc_next_base_fee(
          parent_gas_used :: non_neg_integer(),
          parent_gas_limit :: non_neg_integer(),
          parent_base_fee :: non_neg_integer()
        ) :: non_neg_integer()
  def calc_next_base_fee(parent_gas_used, parent_gas_limit, parent_base_fee) do
    target = div(parent_gas_limit, @elasticity_multiplier)

    cond do
      parent_gas_used == target ->
        parent_base_fee

      parent_gas_used > target ->
        gas_used_delta = parent_gas_used - target

        base_fee_delta =
          max(
            div(parent_base_fee * gas_used_delta, target * @base_fee_change_denominator),
            1
          )

        parent_base_fee + base_fee_delta

      true ->
        gas_used_delta = target - parent_gas_used

        base_fee_delta =
          div(parent_base_fee * gas_used_delta, target * @base_fee_change_denominator)

        max(parent_base_fee - base_fee_delta, 0)
    end
  end
end
