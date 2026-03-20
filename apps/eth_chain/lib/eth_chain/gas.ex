defmodule EthChain.Gas do
  @moduledoc """
  Gas cost calculations for Ethereum transactions.

  Computes intrinsic gas costs based on transaction type, calldata,
  access lists, and init code size per EVM specification.
  """

  alias EthCore.Types.{SignedTransaction, Transaction}

  @tx_gas 21_000
  @tx_create_gas 53_000
  @tx_data_zero 4
  @tx_data_non_zero 16
  @access_list_address 2_400
  @access_list_storage_key 1_900
  @init_code_word_cost 2

  @doc """
  Calculates the intrinsic gas cost of a signed transaction.

  The intrinsic gas is the sum of:
  - Base cost (21000 for call, 53000 for create)
  - Data cost (4 per zero byte, 16 per non-zero byte)
  - Access list cost (2400 per address, 1900 per storage key)
  - Init code cost (2 per 32-byte word, rounded up, for create txs)
  """
  @spec intrinsic_gas(SignedTransaction.t()) :: non_neg_integer()
  def intrinsic_gas(%SignedTransaction{tx: tx}) do
    base_cost(tx) + data_cost(tx) + access_list_cost(tx) + init_code_cost(tx)
  end

  @doc """
  Validates that a child gas limit is within acceptable bounds of the parent.

  The gas limit must satisfy:
  - abs(child - parent) < parent / 1024
  - child >= 5000
  """
  @spec valid_gas_limit?(non_neg_integer(), non_neg_integer()) :: boolean()
  def valid_gas_limit?(child_gas_limit, parent_gas_limit) do
    bound = div(parent_gas_limit, 1024)
    diff = abs(child_gas_limit - parent_gas_limit)
    diff < bound and child_gas_limit >= 5000
  end

  defp base_cost(tx) do
    if creates_contract?(tx), do: @tx_create_gas, else: @tx_gas
  end

  defp creates_contract?(%Transaction.Legacy{to: nil}), do: true
  defp creates_contract?(%Transaction.EIP2930{to: nil}), do: true
  defp creates_contract?(%Transaction.EIP1559{to: nil}), do: true
  defp creates_contract?(%Transaction.EIP7702{to: nil}), do: true
  defp creates_contract?(_tx), do: false

  defp data_cost(tx) do
    data = tx_data(tx)

    for <<byte <- data>>, reduce: 0 do
      acc ->
        if byte == 0, do: acc + @tx_data_zero, else: acc + @tx_data_non_zero
    end
  end

  defp access_list_cost(tx) do
    access_list = tx_access_list(tx)

    Enum.reduce(access_list, 0, fn {_address, storage_keys}, acc ->
      acc + @access_list_address + length(storage_keys) * @access_list_storage_key
    end)
  end

  defp init_code_cost(tx) do
    if creates_contract?(tx) do
      data = tx_data(tx)
      word_count = div(byte_size(data) + 31, 32)
      word_count * @init_code_word_cost
    else
      0
    end
  end

  defp tx_data(%Transaction.Legacy{data: data}), do: data || <<>>
  defp tx_data(%Transaction.EIP2930{data: data}), do: data || <<>>
  defp tx_data(%Transaction.EIP1559{data: data}), do: data || <<>>
  defp tx_data(%Transaction.EIP4844{data: data}), do: data || <<>>
  defp tx_data(%Transaction.EIP7702{data: data}), do: data || <<>>

  defp tx_access_list(%Transaction.Legacy{}), do: []
  defp tx_access_list(%Transaction.EIP2930{access_list: al}), do: al || []
  defp tx_access_list(%Transaction.EIP1559{access_list: al}), do: al || []
  defp tx_access_list(%Transaction.EIP4844{access_list: al}), do: al || []
  defp tx_access_list(%Transaction.EIP7702{access_list: al}), do: al || []
end
