defmodule EthVm.Constants do
  @moduledoc """
  Ethereum protocol gas constants and limits.
  """

  @doc "Base gas cost for a simple transfer transaction."
  @spec tx_gas_cost() :: non_neg_integer()
  def tx_gas_cost, do: 21_000

  @doc "Base gas cost for a contract creation transaction."
  @spec tx_create_gas_cost() :: non_neg_integer()
  def tx_create_gas_cost, do: 53_000

  @doc "Gas cost per zero byte of transaction data."
  @spec tx_data_zero_gas_cost() :: non_neg_integer()
  def tx_data_zero_gas_cost, do: 4

  @doc "Gas cost per non-zero byte of transaction data."
  @spec tx_data_non_zero_gas_cost() :: non_neg_integer()
  def tx_data_non_zero_gas_cost, do: 16

  @doc "Gas cost per address in an access list."
  @spec tx_access_list_address_gas() :: non_neg_integer()
  def tx_access_list_address_gas, do: 2_400

  @doc "Gas cost per storage key in an access list."
  @spec tx_access_list_storage_key_gas() :: non_neg_integer()
  def tx_access_list_storage_key_gas, do: 1_900

  @doc "Maximum deployed contract code size (24 KiB)."
  @spec max_code_size() :: non_neg_integer()
  def max_code_size, do: 0x6000

  @doc "Maximum initcode size (2 * max_code_size)."
  @spec max_initcode_size() :: non_neg_integer()
  def max_initcode_size, do: 2 * max_code_size()
end
