defmodule EthCore.Types.Receipt do
  @moduledoc """
  An Ethereum transaction receipt.
  """

  alias EthCore.Types.Log

  @type t :: %__MODULE__{
          type: 0 | 1 | 2 | 3 | 4,
          status: 0 | 1,
          cumulative_gas_used: non_neg_integer(),
          logs_bloom: <<_::2048>>,
          logs: [Log.t()]
        }

  @enforce_keys [:type, :status, :cumulative_gas_used, :logs_bloom, :logs]
  defstruct [:type, :status, :cumulative_gas_used, :logs_bloom, :logs]
end
