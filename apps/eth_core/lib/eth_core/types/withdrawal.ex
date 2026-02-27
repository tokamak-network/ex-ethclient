defmodule EthCore.Types.Withdrawal do
  @moduledoc """
  EIP-4895 withdrawal type for beacon chain withdrawals.
  """

  alias EthCore.Types.Address

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          validator_index: non_neg_integer(),
          address: Address.t(),
          amount: non_neg_integer()
        }

  @enforce_keys [:index, :validator_index, :address, :amount]
  defstruct [:index, :validator_index, :address, :amount]
end
