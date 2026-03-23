defmodule EthVm.CallExecutorTest do
  use ExUnit.Case, async: true

  alias EthVm.CallExecutor

  describe "execute_call/3" do
    test "call to address returns output" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<1, 2, 3, 4>>,
        gas_price: 0
      }

      assert {:ok, output} = CallExecutor.execute_call(call_params, nil, evm_module: EthVm.Mock)
      assert is_binary(output)
    end

    test "call with empty data succeeds" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<>>,
        gas_price: 0
      }

      assert {:ok, output} = CallExecutor.execute_call(call_params, nil, evm_module: EthVm.Mock)
      assert output == <<>>
    end

    test "call with no store falls back gracefully" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 100,
        data: <<>>
      }

      assert {:ok, _output} =
               CallExecutor.execute_call(call_params, nil, evm_module: EthVm.Mock)
    end

    test "returns error when EVM execution reverts" do
      defmodule RevertingEvm do
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
               CallExecutor.execute_call(call_params, nil, evm_module: RevertingEvm)
    end

    test "returns error when EVM returns error tuple" do
      defmodule ErrorEvm do
        @moduledoc false
        @behaviour EthVm.Evm

        @impl true
        def execute_transaction(_env, _tx, _state) do
          {:error, :nif_not_loaded}
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

      assert {:error, :nif_not_loaded} =
               CallExecutor.execute_call(call_params, nil, evm_module: ErrorEvm)
    end

    test "respects custom block gas limit" do
      call_params = %{
        from: <<1::160>>,
        to: <<2::160>>,
        value: 0,
        data: <<>>
      }

      assert {:ok, _output} =
               CallExecutor.execute_call(call_params, nil,
                 evm_module: EthVm.Mock,
                 block_gas_limit: 100_000
               )
    end
  end
end
