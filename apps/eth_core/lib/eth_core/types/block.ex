defmodule EthCore.Types.Block do
  @moduledoc """
  An Ethereum block consisting of a header, transactions, and ommers.
  """

  alias EthCore.Types.{BlockHeader, SignedTransaction, Withdrawal}

  @type t :: %__MODULE__{
          header: BlockHeader.t(),
          transactions: [SignedTransaction.t()],
          ommers: [BlockHeader.t()],
          withdrawals: [Withdrawal.t()] | nil
        }

  @enforce_keys [:header]
  defstruct [
    :header,
    transactions: [],
    ommers: [],
    withdrawals: nil
  ]
end
