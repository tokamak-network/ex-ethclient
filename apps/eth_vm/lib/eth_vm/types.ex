defmodule EthVm.Types do
  @moduledoc """
  Types used by the EVM execution engine.
  """

  @typedoc "Gas amount (non-negative integer)."
  @type gas :: non_neg_integer()

  @typedoc "Wei amount (non-negative integer)."
  @type wei :: non_neg_integer()

  defmodule ExecutionResult do
    @moduledoc """
    The result of executing a single transaction.
    """

    @type t :: %__MODULE__{
            success: boolean(),
            gas_used: non_neg_integer(),
            gas_refunded: non_neg_integer(),
            output: binary(),
            logs: [EthCore.Types.Log.t()],
            error: atom() | nil
          }

    defstruct success: false,
              gas_used: 0,
              gas_refunded: 0,
              output: <<>>,
              logs: [],
              error: nil
  end

  defmodule BlockExecutionResult do
    @moduledoc """
    The result of executing all transactions in a block.
    """

    @type account_update :: %{
            nonce: non_neg_integer(),
            balance: non_neg_integer(),
            code: binary() | nil,
            storage: %{binary() => binary()}
          }

    @type t :: %__MODULE__{
            receipts: [EthCore.Types.Receipt.t()],
            gas_used: non_neg_integer(),
            account_updates: %{
              EthCore.Types.Address.t() => account_update()
            },
            logs: [EthCore.Types.Log.t()]
          }

    defstruct receipts: [],
              gas_used: 0,
              account_updates: %{},
              logs: []
  end

  defmodule Environment do
    @moduledoc """
    The block-level execution environment passed to the EVM.
    """

    @type t :: %__MODULE__{
            coinbase: binary(),
            gas_limit: non_neg_integer(),
            number: non_neg_integer(),
            timestamp: non_neg_integer(),
            difficulty: non_neg_integer(),
            base_fee_per_gas: non_neg_integer(),
            chain_id: non_neg_integer(),
            block_hash_lookup: (non_neg_integer() -> binary() | nil)
          }

    defstruct [
      :coinbase,
      :gas_limit,
      :number,
      :timestamp,
      difficulty: 0,
      base_fee_per_gas: 0,
      chain_id: 1,
      block_hash_lookup: nil
    ]
  end
end
