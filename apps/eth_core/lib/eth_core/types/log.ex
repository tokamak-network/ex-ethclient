defmodule EthCore.Types.Log do
  @moduledoc """
  An Ethereum log entry emitted during transaction execution.
  """

  alias EthCore.Types.Address

  @type t :: %__MODULE__{
          address: Address.t(),
          topics: [<<_::256>>],
          data: binary()
        }

  @enforce_keys [:address, :topics, :data]
  defstruct [:address, :topics, :data]
end
