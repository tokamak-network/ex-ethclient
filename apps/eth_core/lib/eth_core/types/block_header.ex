defmodule EthCore.Types.BlockHeader do
  @moduledoc """
  Ethereum block header containing all consensus-critical fields.
  Supports post-Shanghai (withdrawals_root), post-Cancun (blob fields),
  and post-Prague (requests_hash, EIP-7685).
  """

  alias EthCore.Types.{Address, Hash}

  @type t :: %__MODULE__{
          parent_hash: Hash.t(),
          ommers_hash: Hash.t(),
          coinbase: Address.t(),
          state_root: Hash.t(),
          transactions_root: Hash.t(),
          receipts_root: Hash.t(),
          logs_bloom: <<_::2048>>,
          difficulty: non_neg_integer(),
          number: non_neg_integer(),
          gas_limit: non_neg_integer(),
          gas_used: non_neg_integer(),
          timestamp: non_neg_integer(),
          extra_data: binary(),
          mix_hash: Hash.t(),
          nonce: <<_::64>>,
          # EIP-1559
          base_fee_per_gas: non_neg_integer() | nil,
          # EIP-4895 (Shanghai)
          withdrawals_root: Hash.t() | nil,
          # EIP-4844 (Cancun)
          blob_gas_used: non_neg_integer() | nil,
          excess_blob_gas: non_neg_integer() | nil,
          parent_beacon_block_root: Hash.t() | nil,
          # EIP-7685 (Prague/Pectra)
          requests_hash: Hash.t() | nil
        }

  @enforce_keys [
    :parent_hash,
    :ommers_hash,
    :coinbase,
    :state_root,
    :transactions_root,
    :receipts_root,
    :logs_bloom,
    :difficulty,
    :number,
    :gas_limit,
    :gas_used,
    :timestamp,
    :extra_data,
    :mix_hash,
    :nonce
  ]
  defstruct [
    :parent_hash,
    :ommers_hash,
    :coinbase,
    :state_root,
    :transactions_root,
    :receipts_root,
    :logs_bloom,
    :difficulty,
    :number,
    :gas_limit,
    :gas_used,
    :timestamp,
    :extra_data,
    :mix_hash,
    :nonce,
    :base_fee_per_gas,
    :withdrawals_root,
    :blob_gas_used,
    :excess_blob_gas,
    :parent_beacon_block_root,
    :requests_hash
  ]
end
