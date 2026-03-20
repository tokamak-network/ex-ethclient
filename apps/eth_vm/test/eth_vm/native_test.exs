defmodule EthVm.NativeTest do
  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Native

  # Use addresses > 0x09 to avoid precompile addresses (0x01-0x09)
  @sender <<0xAA::8, 0::152>>
  @receiver <<0xBB::8, 0::152>>

  describe "evm_version/0" do
    test "returns a version string containing revm" do
      version = Native.evm_version()
      assert is_binary(version)
      assert String.contains?(version, "ethvm-native")
      assert String.contains?(version, "revm")
    end
  end

  describe "execute_simple_tx/5" do
    test "returns success for valid transfer" do
      assert {:ok, result} = Native.execute_simple_tx(@sender, @receiver, 1000, 21_000, 1)
      assert result[:gas_used] == 21_000
      assert result[:success] == true
    end

    test "returns error for invalid from address" do
      assert {:error, :invalid_address} =
               Native.execute_simple_tx(<<1, 2, 3>>, @receiver, 0, 21_000, 1)
    end

    test "returns error for invalid to address" do
      assert {:error, :invalid_address} =
               Native.execute_simple_tx(@sender, <<1, 2>>, 0, 21_000, 1)
    end

    test "returns output as binary" do
      assert {:ok, result} = Native.execute_simple_tx(@sender, @receiver, 0, 21_000, 1)
      assert is_binary(result[:output])
    end
  end

  describe "execute_call/6" do
    test "returns success for valid call with data" do
      data = <<0xA9, 0x05, 0x9C, 0xBB>>

      assert {:ok, result} = Native.execute_call(@sender, @receiver, data, 0, 100_000, 1)
      assert result[:success] == true
      assert result[:gas_used] >= 21_000
    end

    test "returns success for call with empty data" do
      assert {:ok, result} = Native.execute_call(@sender, @receiver, <<>>, 0, 21_000, 1)
      assert result[:gas_used] == 21_000
    end

    test "returns error for invalid address" do
      assert {:error, :invalid_address} =
               Native.execute_call(<<1>>, @receiver, <<>>, 0, 21_000, 1)
    end
  end

  describe "execute_tx/9" do
    test "simple value transfer via execute_tx" do
      # value = 1000 wei as big-endian
      value = <<3, 232>>
      gas_limit = 21_000
      gas_price = <<1>>
      data = <<>>
      code = <<>>
      nonce = 0
      # 10 ETH in wei
      balance = <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

      assert {:ok, result} =
               Native.execute_tx(
                 @sender,
                 @receiver,
                 value,
                 gas_limit,
                 gas_price,
                 data,
                 code,
                 nonce,
                 balance
               )

      assert result[:success] == true
      assert result[:gas_used] == 21_000
      assert is_binary(result[:output])
      assert is_list(result[:logs])
      assert is_map(result[:state_changes])
    end

    test "contract execution with bytecode" do
      value = <<>>
      gas_limit = 100_000
      gas_price = <<>>
      data = <<>>

      # Bytecode: PUSH1 0x42 PUSH1 0x00 MSTORE PUSH1 0x20 PUSH1 0x00 RETURN
      # This stores 0x42 at memory[0] and returns 32 bytes from memory[0]
      code = <<0x60, 0x42, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3>>
      nonce = 0
      balance = <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

      assert {:ok, result} =
               Native.execute_tx(
                 @sender,
                 @receiver,
                 value,
                 gas_limit,
                 gas_price,
                 data,
                 code,
                 nonce,
                 balance
               )

      assert result[:success] == true
      assert result[:gas_used] > 21_000

      # The output should be 32 bytes with 0x42 at the end
      output = result[:output]
      assert byte_size(output) == 32
      assert :binary.at(output, 31) == 0x42
    end

    test "contract creation with empty to" do
      # Empty to = contract creation
      to = <<>>
      value = <<>>
      gas_limit = 100_000
      gas_price = <<>>

      # Simple contract: PUSH1 0x00 PUSH1 0x00 RETURN (returns empty)
      data = <<0x60, 0x00, 0x60, 0x00, 0xF3>>
      code = <<>>
      nonce = 0
      balance = <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

      assert {:ok, result} =
               Native.execute_tx(
                 @sender,
                 to,
                 value,
                 gas_limit,
                 gas_price,
                 data,
                 code,
                 nonce,
                 balance
               )

      assert result[:success] == true
      assert result[:gas_used] > 0
    end

    test "returns error for invalid from address" do
      assert {:error, :invalid_address} =
               Native.execute_tx(
                 <<1, 2, 3>>,
                 @receiver,
                 <<>>,
                 21_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 <<>>
               )
    end

    test "gas metering is reasonable for different operations" do
      balance = <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

      # Simple transfer
      {:ok, transfer} =
        Native.execute_tx(@sender, @receiver, <<1>>, 21_000, <<>>, <<>>, <<>>, 0, balance)

      assert transfer[:gas_used] == 21_000

      # Contract with computation (ADD operations)
      # PUSH1 1 PUSH1 2 ADD POP STOP
      code = <<0x60, 0x01, 0x60, 0x02, 0x01, 0x50, 0x00>>

      {:ok, compute} =
        Native.execute_tx(@sender, @receiver, <<>>, 100_000, <<>>, <<>>, code, 0, balance)

      # Should use more than base tx gas due to contract execution
      assert compute[:gas_used] > 21_000
    end

    test "state_changes tracks account modifications" do
      value = <<3, 232>>
      balance = <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

      {:ok, result} =
        Native.execute_tx(@sender, @receiver, value, 21_000, <<>>, <<>>, <<>>, 0, balance)

      state_changes = result[:state_changes]
      assert is_map(state_changes)
      # Should have at least the sender and receiver in state changes
      assert map_size(state_changes) >= 2
    end
  end
end
