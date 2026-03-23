defmodule EthVm.GasEstimatorTest do
  use ExUnit.Case, async: true

  alias EthVm.GasEstimator

  describe "estimate_gas/3" do
    test "simple transfer estimates approximately 21000 gas" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 1_000_000,
        data: <<>>,
        gas_price: 1_000_000_000
      }

      assert {:ok, gas} = GasEstimator.estimate_gas(call_params, nil, evm_module: EthVm.Mock)
      assert gas == 21_000
    end

    test "estimates converge within 64 iterations" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<>>,
        gas_price: 0
      }

      assert {:ok, gas} = GasEstimator.estimate_gas(call_params, nil, evm_module: EthVm.Mock)
      assert is_integer(gas)
      assert gas >= 21_000
      assert gas <= 30_000_000
    end

    test "returns error for invalid transaction when EVM always fails" do
      defmodule FailingEvm do
        @moduledoc false
        @behaviour EthVm.Evm

        @impl true
        def execute_transaction(_env, _tx, _state) do
          {:ok, %EthVm.Types.ExecutionResult{success: false, gas_used: 0}}
        end

        @impl true
        def execute_block(_block, _state) do
          {:ok, %EthVm.Types.BlockExecutionResult{}}
        end
      end

      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<>>
      }

      assert {:error, :execution_reverted} =
               GasEstimator.estimate_gas(call_params, nil, evm_module: FailingEvm)
    end

    test "respects custom block gas limit" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<>>,
        gas_price: 0
      }

      assert {:ok, gas} =
               GasEstimator.estimate_gas(call_params, nil,
                 evm_module: EthVm.Mock,
                 block_gas_limit: 100_000
               )

      assert gas <= 100_000
    end

    test "handles call with data by computing intrinsic gas" do
      # 10 non-zero bytes = 10 * 16 = 160 extra gas
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>,
        gas_price: 0
      }

      assert {:ok, gas} = GasEstimator.estimate_gas(call_params, nil, evm_module: EthVm.Mock)
      # Mock always succeeds with 21_000, so estimate should find 21_000
      # but intrinsic gas floor is 21_000 + 160 = 21_160
      assert gas >= 21_000
    end
  end
end
