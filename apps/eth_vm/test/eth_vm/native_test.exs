defmodule EthVm.NativeTest do
  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Native

  describe "evm_version/0" do
    test "returns a version string" do
      version = Native.evm_version()
      assert is_binary(version)
      assert String.contains?(version, "ethvm-native")
    end
  end

  describe "execute_simple_tx/5" do
    test "returns success for valid transfer" do
      from = <<1::160>>
      to = <<2::160>>

      assert {:ok, result} = Native.execute_simple_tx(from, to, 1000, 21_000, 1)
      assert result[:gas_used] == 21_000
      assert result[:success] == true
    end

    test "returns error for invalid from address" do
      assert {:error, :invalid_address} =
               Native.execute_simple_tx(<<1, 2, 3>>, <<2::160>>, 0, 21_000, 1)
    end

    test "returns error for invalid to address" do
      assert {:error, :invalid_address} =
               Native.execute_simple_tx(<<1::160>>, <<1, 2>>, 0, 21_000, 1)
    end

    test "returns error when gas limit is insufficient" do
      assert {:error, :out_of_gas} =
               Native.execute_simple_tx(<<1::160>>, <<2::160>>, 0, 20_000, 1)
    end
  end

  describe "execute_call/6" do
    test "returns success for valid call with data" do
      from = <<1::160>>
      to = <<2::160>>
      data = <<0xA9, 0x05, 0x9C, 0xBB>>

      assert {:ok, result} = Native.execute_call(from, to, data, 0, 100_000, 1)
      assert result[:success] == true
      assert result[:gas_used] > 21_000
    end

    test "returns success for call with empty data" do
      from = <<1::160>>
      to = <<2::160>>

      assert {:ok, result} = Native.execute_call(from, to, <<>>, 0, 21_000, 1)
      assert result[:gas_used] == 21_000
    end

    test "returns error for invalid address" do
      assert {:error, :invalid_address} =
               Native.execute_call(<<1>>, <<2::160>>, <<>>, 0, 21_000, 1)
    end

    test "returns error when gas limit is insufficient" do
      assert {:error, :out_of_gas} =
               Native.execute_call(<<1::160>>, <<2::160>>, <<>>, 0, 20_000, 1)
    end
  end
end
