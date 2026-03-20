defmodule EthVm.TypesTest do
  use ExUnit.Case, async: true

  alias EthVm.Types.{BlockExecutionResult, Environment, ExecutionResult}

  describe "ExecutionResult" do
    test "default struct values" do
      result = %ExecutionResult{}
      assert result.success == false
      assert result.gas_used == 0
      assert result.gas_refunded == 0
      assert result.output == <<>>
      assert result.logs == []
      assert result.error == nil
    end

    test "can be created with custom values" do
      result = %ExecutionResult{
        success: true,
        gas_used: 21_000,
        gas_refunded: 500,
        output: <<1, 2, 3>>,
        logs: [],
        error: nil
      }

      assert result.success == true
      assert result.gas_used == 21_000
      assert result.gas_refunded == 500
      assert result.output == <<1, 2, 3>>
    end
  end

  describe "BlockExecutionResult" do
    test "default struct values" do
      result = %BlockExecutionResult{}
      assert result.receipts == []
      assert result.gas_used == 0
      assert result.account_updates == %{}
      assert result.logs == []
    end

    test "can be created with custom values" do
      result = %BlockExecutionResult{
        gas_used: 42_000,
        account_updates: %{},
        logs: []
      }

      assert result.gas_used == 42_000
    end
  end

  describe "Environment" do
    test "default struct values" do
      env = %Environment{}
      assert env.coinbase == nil
      assert env.gas_limit == nil
      assert env.number == nil
      assert env.timestamp == nil
      assert env.difficulty == 0
      assert env.base_fee_per_gas == 0
      assert env.chain_id == 1
      assert env.block_hash_lookup == nil
    end

    test "can be created with all fields" do
      lookup = fn _num -> <<0::256>> end

      env = %Environment{
        coinbase: <<1::160>>,
        gas_limit: 30_000_000,
        number: 100,
        timestamp: 1_700_000_000,
        difficulty: 0,
        base_fee_per_gas: 1_000_000_000,
        chain_id: 1,
        block_hash_lookup: lookup
      }

      assert env.coinbase == <<1::160>>
      assert env.gas_limit == 30_000_000
      assert env.number == 100
      assert is_function(env.block_hash_lookup, 1)
    end
  end
end
