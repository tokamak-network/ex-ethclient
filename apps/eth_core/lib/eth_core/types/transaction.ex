defmodule EthCore.Types.Transaction do
  @moduledoc """
  Ethereum transaction types.

  Supports:
  - Legacy (pre-EIP-155 and EIP-155) - Type 0
  - EIP-2930 (Type 1) - Access list transactions
  - EIP-1559 (Type 2) - Dynamic fee transactions
  - EIP-4844 (Type 3) - Blob transactions (Dencun)
  - EIP-7702 (Type 4) - Set-code transactions (Prague/Pectra)
  """

  alias EthCore.Types.Address
  alias EthCore.Types.Authorization

  @type access_list_entry :: {Address.t(), [<<_::256>>]}

  @type legacy :: %__MODULE__.Legacy{
          nonce: non_neg_integer(),
          gas_price: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: Address.t() | nil,
          value: non_neg_integer(),
          data: binary()
        }

  @type eip2930 :: %__MODULE__.EIP2930{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          gas_price: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: Address.t() | nil,
          value: non_neg_integer(),
          data: binary(),
          access_list: [access_list_entry()]
        }

  @type eip1559 :: %__MODULE__.EIP1559{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: Address.t() | nil,
          value: non_neg_integer(),
          data: binary(),
          access_list: [access_list_entry()]
        }

  @type eip4844 :: %__MODULE__.EIP4844{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: Address.t(),
          value: non_neg_integer(),
          data: binary(),
          access_list: [access_list_entry()],
          max_fee_per_blob_gas: non_neg_integer(),
          blob_versioned_hashes: [<<_::256>>]
        }

  @type eip7702 :: %__MODULE__.EIP7702{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: Address.t() | nil,
          value: non_neg_integer(),
          data: binary(),
          access_list: [access_list_entry()],
          authorization_list: [Authorization.t()]
        }

  @type t :: legacy() | eip2930() | eip1559() | eip4844() | eip7702()

  defmodule Legacy do
    @moduledoc "Legacy (Type 0) transaction."
    @enforce_keys [:nonce, :gas_price, :gas_limit, :value, :data]
    defstruct [:nonce, :gas_price, :gas_limit, :to, :value, :data]
  end

  defmodule EIP2930 do
    @moduledoc "EIP-2930 (Type 1) access list transaction."
    @enforce_keys [:chain_id, :nonce, :gas_price, :gas_limit, :value, :data, :access_list]
    defstruct [:chain_id, :nonce, :gas_price, :gas_limit, :to, :value, :data, :access_list]
  end

  defmodule EIP1559 do
    @moduledoc "EIP-1559 (Type 2) dynamic fee transaction."
    @enforce_keys [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :value,
      :data,
      :access_list
    ]
    defstruct [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :to,
      :value,
      :data,
      :access_list
    ]
  end

  defmodule EIP4844 do
    @moduledoc "EIP-4844 (Type 3) blob transaction (Dencun)."
    @enforce_keys [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :to,
      :value,
      :data,
      :access_list,
      :max_fee_per_blob_gas,
      :blob_versioned_hashes
    ]
    defstruct [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :to,
      :value,
      :data,
      :access_list,
      :max_fee_per_blob_gas,
      :blob_versioned_hashes
    ]
  end

  defmodule EIP7702 do
    @moduledoc "EIP-7702 (Type 4) set-code transaction (Prague/Pectra)."
    @enforce_keys [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :value,
      :data,
      :access_list,
      :authorization_list
    ]
    defstruct [
      :chain_id,
      :nonce,
      :max_priority_fee_per_gas,
      :max_fee_per_gas,
      :gas_limit,
      :to,
      :value,
      :data,
      :access_list,
      :authorization_list
    ]
  end

  @doc "Returns the transaction type byte."
  @spec type(t()) :: 0 | 1 | 2 | 3 | 4
  def type(%Legacy{}), do: 0
  def type(%EIP2930{}), do: 1
  def type(%EIP1559{}), do: 2
  def type(%EIP4844{}), do: 3
  def type(%EIP7702{}), do: 4
end
