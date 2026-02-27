defmodule EthCore.Types.SignedTransaction do
  @moduledoc """
  A signed Ethereum transaction containing the original transaction and signature components.
  """

  alias EthCore.Types.Transaction

  @type t :: %__MODULE__{
          tx: Transaction.t(),
          v: non_neg_integer(),
          r: non_neg_integer(),
          s: non_neg_integer()
        }

  @enforce_keys [:tx, :v, :r, :s]
  defstruct [:tx, :v, :r, :s]

  @doc "Creates a new signed transaction."
  @spec new(Transaction.t(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(tx, v, r, s) do
    %__MODULE__{tx: tx, v: v, r: r, s: s}
  end

  @doc "Computes the transaction hash (keccak256 of the signed RLP encoding)."
  @spec tx_hash(t()) :: <<_::256>>
  def tx_hash(%__MODULE__{} = signed_tx) do
    signed_tx
    |> EthCore.RLP.encode_signed()
    |> EthCrypto.Hash.keccak256()
  end
end
