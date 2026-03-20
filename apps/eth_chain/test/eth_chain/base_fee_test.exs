defmodule EthChain.BaseFeeTest do
  use ExUnit.Case, async: true

  alias EthChain.BaseFee

  describe "calc_next_base_fee/3" do
    test "base fee unchanged when gas_used equals target" do
      # target = 30_000_000 / 2 = 15_000_000
      assert BaseFee.calc_next_base_fee(15_000_000, 30_000_000, 1_000_000_000) ==
               1_000_000_000
    end

    test "base fee increases when gas_used exceeds target" do
      # target = 15_000_000
      # gas_used = 20_000_000 > target
      # delta = 20_000_000 - 15_000_000 = 5_000_000
      # base_fee_delta = max(1_000_000_000 * 5_000_000 / (15_000_000 * 8), 1)
      #                = max(41_666_666, 1) = 41_666_666
      # new = 1_000_000_000 + 41_666_666 = 1_041_666_666
      result = BaseFee.calc_next_base_fee(20_000_000, 30_000_000, 1_000_000_000)
      assert result == 1_041_666_666
    end

    test "base fee decreases when gas_used is below target" do
      # target = 15_000_000
      # gas_used = 10_000_000 < target
      # delta = 15_000_000 - 10_000_000 = 5_000_000
      # base_fee_delta = 1_000_000_000 * 5_000_000 / (15_000_000 * 8) = 41_666_666
      # new = 1_000_000_000 - 41_666_666 = 958_333_334
      result = BaseFee.calc_next_base_fee(10_000_000, 30_000_000, 1_000_000_000)
      assert result == 958_333_334
    end

    test "base fee does not go below zero" do
      # target = 500, gas_used = 0
      # delta = 500
      # base_fee_delta = 10 * 500 / (500 * 8) = 1
      # new = max(10 - 1, 0) = 9
      # Actually let's use a case that would go negative
      result = BaseFee.calc_next_base_fee(0, 1000, 1)
      assert result >= 0
    end

    test "base fee increases by at least 1 when above target" do
      # Even with very small base fee, increase is at least 1
      # target = 5, gas_used = 6
      # delta = 1, base_fee_delta = max(1 * 1 / (5 * 8), 1) = max(0, 1) = 1
      result = BaseFee.calc_next_base_fee(6, 10, 1)
      assert result == 2
    end

    test "full block doubles the base fee change rate" do
      # gas_used = gas_limit (full block)
      # target = 15_000_000
      # delta = 30_000_000 - 15_000_000 = 15_000_000
      # base_fee_delta = max(1_000_000_000 * 15_000_000 / (15_000_000 * 8), 1)
      #                = 125_000_000
      result = BaseFee.calc_next_base_fee(30_000_000, 30_000_000, 1_000_000_000)
      assert result == 1_125_000_000
    end

    test "empty block with zero gas_used" do
      # target = 15_000_000, gas_used = 0
      # delta = 15_000_000
      # base_fee_delta = 1_000_000_000 * 15_000_000 / (15_000_000 * 8) = 125_000_000
      result = BaseFee.calc_next_base_fee(0, 30_000_000, 1_000_000_000)
      assert result == 875_000_000
    end
  end
end
