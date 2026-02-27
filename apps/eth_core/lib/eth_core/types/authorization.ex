defmodule EthCore.Types.Authorization do
  @moduledoc """
  EIP-7702 authorization tuple for set-code transactions.
  """

  alias EthCore.Types.Address

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          address: Address.t(),
          nonce: non_neg_integer(),
          y_parity: 0 | 1,
          r: non_neg_integer(),
          s: non_neg_integer()
        }

  @enforce_keys [:chain_id, :address, :nonce, :y_parity, :r, :s]
  defstruct [:chain_id, :address, :nonce, :y_parity, :r, :s]
end
