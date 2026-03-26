defmodule EthVm.NifStateTest do
  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Native
  alias EthVm.StateLoader

  @from_addr <<1::160>>
  @to_addr <<2::160>>

  describe "execute_tx_with_state/8" do
    test "simple transfer with pre-loaded state" do
      # Build state with sender having enough balance
      sender_balance = 1_000_000_000_000_000_000

      accounts = %{
        @from_addr => %{nonce: 0, balance: sender_balance, code: <<>>, storage: %{}},
        @to_addr => %{nonce: 0, balance: 0, code: <<>>, storage: %{}}
      }

      state_binary = StateLoader.serialize_state(accounts)
      transfer_value = 1_000_000

      result =
        Native.execute_tx_with_state(
          state_binary,
          @from_addr,
          @to_addr,
          <<transfer_value::unsigned-big-256>>,
          21_000,
          <<0::unsigned-big-256>>,
          <<>>,
          0
        )

      assert {:ok, map} = result
      assert map.success == true
      assert map.gas_used == 21_000
      assert is_map(map.state_changes)
    end

    test "contract execution with pre-loaded state and code" do
      # Simple contract: PUSH1 0x42, PUSH1 0x00, MSTORE, PUSH1 0x20, PUSH1 0x00, RETURN
      # Returns 0x42 as a 32-byte word
      contract_code = <<0x60, 0x42, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3>>

      sender_balance = 1_000_000_000_000_000_000

      accounts = %{
        @from_addr => %{nonce: 0, balance: sender_balance, code: <<>>, storage: %{}},
        @to_addr => %{nonce: 0, balance: 0, code: contract_code, storage: %{}}
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_with_state(
          state_binary,
          @from_addr,
          @to_addr,
          <<0::unsigned-big-256>>,
          100_000,
          <<0::unsigned-big-256>>,
          <<>>,
          0
        )

      assert {:ok, map} = result
      assert map.success == true
      assert map.gas_used > 0
      # Output should be 32 bytes with 0x42 at the end
      assert byte_size(map.output) == 32
      assert :binary.decode_unsigned(map.output) == 0x42
    end

    test "returns state changes after execution" do
      sender_balance = 1_000_000_000_000_000_000

      accounts = %{
        @from_addr => %{nonce: 0, balance: sender_balance, code: <<>>, storage: %{}},
        @to_addr => %{nonce: 0, balance: 0, code: <<>>, storage: %{}}
      }

      state_binary = StateLoader.serialize_state(accounts)

      assert {:ok, map} =
               Native.execute_tx_with_state(
                 state_binary,
                 @from_addr,
                 @to_addr,
                 <<1000::unsigned-big-256>>,
                 21_000,
                 <<0::unsigned-big-256>>,
                 <<>>,
                 0
               )

      assert map.success == true
      assert is_map(map.state_changes)
      # Should have state changes for at least sender and recipient
      assert map_size(map.state_changes) >= 2
    end

    test "handles empty state data" do
      result =
        Native.execute_tx_with_state(
          <<>>,
          @from_addr,
          @to_addr,
          <<0::unsigned-big-256>>,
          21_000,
          <<0::unsigned-big-256>>,
          <<>>,
          0
        )

      # Should succeed (empty state = no accounts pre-loaded)
      assert {:ok, _map} = result
    end

    test "rejects invalid from address" do
      result =
        Native.execute_tx_with_state(
          <<>>,
          <<1, 2, 3>>,
          @to_addr,
          <<0::unsigned-big-256>>,
          21_000,
          <<0::unsigned-big-256>>,
          <<>>,
          0
        )

      assert {:error, :invalid_address} = result
    end

    test "handles contract creation with empty to" do
      # Simple contract creation: PUSH1 0x00 PUSH1 0x00 RETURN (deploys empty contract)
      init_code = <<0x60, 0x00, 0x60, 0x00, 0xF3>>
      sender_balance = 1_000_000_000_000_000_000

      accounts = %{
        @from_addr => %{nonce: 0, balance: sender_balance, code: <<>>, storage: %{}}
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_with_state(
          state_binary,
          @from_addr,
          <<>>,
          <<0::unsigned-big-256>>,
          100_000,
          <<0::unsigned-big-256>>,
          init_code,
          0
        )

      assert {:ok, map} = result
      assert map.success == true
    end
  end
end
