defmodule EthChain.WithdrawalProcessor do
  @moduledoc """
  Processes beacon chain withdrawals per EIP-4895.

  After the Shanghai fork, each block may contain a list of withdrawals
  from the beacon chain. Each withdrawal credits the specified address
  with the given amount (converted from Gwei to Wei).
  """

  alias EthCore.Types.{Account, Withdrawal}

  @gwei_to_wei 1_000_000_000

  @doc """
  Processes a list of withdrawals, updating account balances.

  For each withdrawal:
  1. Converts amount from Gwei to Wei (amount * 1_000_000_000)
  2. Adds to the recipient's balance
  3. Creates the account with zero nonce if it does not exist

  Returns a map of address => %Account{} with updated balances.
  """
  @spec process_withdrawals([Withdrawal.t()], %{binary() => Account.t()}) ::
          %{binary() => Account.t()}
  def process_withdrawals(withdrawals, account_state) when is_list(withdrawals) do
    Enum.reduce(withdrawals, account_state, fn %Withdrawal{} = w, state ->
      wei_amount = w.amount * @gwei_to_wei
      address = w.address

      account =
        case Map.get(state, address) do
          nil -> Account.new()
          existing -> existing
        end

      updated = %{account | balance: account.balance + wei_amount}
      Map.put(state, address, updated)
    end)
  end

  @doc """
  Converts withdrawal balance updates to the account_updates map format
  used by StateManager.

  Returns a map of address => %{balance: new_balance, nonce: nonce}.
  """
  @spec to_account_updates(%{binary() => Account.t()}, %{binary() => Account.t()}) ::
          %{binary() => map()}
  def to_account_updates(updated_state, original_state) do
    Enum.reduce(updated_state, %{}, fn {address, account}, acc ->
      original = Map.get(original_state, address)

      if original != account do
        Map.put(acc, address, %{balance: account.balance, nonce: account.nonce})
      else
        acc
      end
    end)
  end
end
