defmodule EthVm.ConstantsTest do
  use ExUnit.Case, async: true

  alias EthVm.Constants

  describe "transaction gas costs" do
    test "tx_gas_cost is 21_000" do
      assert Constants.tx_gas_cost() == 21_000
    end

    test "tx_create_gas_cost is 53_000" do
      assert Constants.tx_create_gas_cost() == 53_000
    end

    test "tx_data_zero_gas_cost is 4" do
      assert Constants.tx_data_zero_gas_cost() == 4
    end

    test "tx_data_non_zero_gas_cost is 16" do
      assert Constants.tx_data_non_zero_gas_cost() == 16
    end
  end

  describe "access list gas costs" do
    test "tx_access_list_address_gas is 2_400" do
      assert Constants.tx_access_list_address_gas() == 2_400
    end

    test "tx_access_list_storage_key_gas is 1_900" do
      assert Constants.tx_access_list_storage_key_gas() == 1_900
    end
  end

  describe "code size limits" do
    test "max_code_size is 24_576 (0x6000)" do
      assert Constants.max_code_size() == 24_576
    end

    test "max_initcode_size is twice max_code_size" do
      assert Constants.max_initcode_size() == 2 * Constants.max_code_size()
      assert Constants.max_initcode_size() == 49_152
    end
  end
end
