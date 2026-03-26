defmodule EthVm.Native do
  @moduledoc """
  Rust NIF bindings for EVM execution.

  Provides low-level access to the Rust-based EVM engine backed by revm.
  """

  use Rustler,
    otp_app: :eth_vm,
    crate: "ethvm_native"

  @doc "Executes a transaction with the real EVM (revm)."
  @spec execute_tx(
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary()
        ) ::
          {:ok, map()} | {:error, atom()}
  def execute_tx(_from, _to, _value, _gas_limit, _gas_price, _data, _code, _nonce, _balance),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "Executes a simple value transfer (no contract interaction)."
  @spec execute_simple_tx(
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, atom()}
  def execute_simple_tx(_from, _to, _value, _gas_limit, _gas_price),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc "Executes a contract call with input data."
  @spec execute_call(
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, map()} | {:error, atom()}
  def execute_call(_from, _to, _data, _value, _gas_limit, _gas_price),
    do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Executes a transaction with full type support (Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702).

  Parameters:
    - tx_type: 0=Legacy, 1=EIP-2930, 2=EIP-1559, 3=EIP-4844, 4=EIP-7702
    - from: 20-byte sender address
    - to: 20-byte recipient (empty binary for contract creation)
    - value: big-endian U256 value in wei
    - gas_limit: gas limit as integer
    - gas_price: big-endian U256 (gas_price for legacy/2930, max_fee_per_gas for 1559+)
    - max_priority_fee: big-endian U256 (empty for legacy/2930)
    - max_fee_per_blob_gas: big-endian U256 (empty unless EIP-4844)
    - data: calldata binary
    - code: contract bytecode at target address
    - nonce: sender nonce as integer
    - balance: big-endian U256 sender balance
    - access_list_data: binary-encoded access list
    - blob_hashes_data: concatenated 32-byte blob versioned hashes
  """
  @spec execute_tx_v2(
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          binary()
        ) :: {:ok, map()} | {:error, atom()}
  def execute_tx_v2(
        _tx_type,
        _from,
        _to,
        _value,
        _gas_limit,
        _gas_price,
        _max_priority_fee,
        _max_fee_per_blob_gas,
        _data,
        _code,
        _nonce,
        _balance,
        _access_list_data,
        _blob_hashes_data
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Executes a transaction with full block context and pre-loaded state.

  This is the primary NIF for real mainnet transaction execution. The SpecId
  is determined automatically from block number and timestamp using mainnet
  fork boundaries.

  Parameters:
    Block context:
    - block_number: block height
    - block_timestamp: UNIX timestamp
    - coinbase: 20-byte beneficiary address
    - base_fee: base fee per gas as integer (u64)
    - prev_randao: 32-byte prevrandao (or empty)
    - block_gas_limit: block gas limit
    - excess_blob_gas: excess blob gas (0 if pre-Cancun)

    Transaction fields:
    - tx_type: 0=Legacy, 1=EIP-2930, 2=EIP-1559, 3=EIP-4844, 4=EIP-7702
    - from: 20-byte sender address
    - to: 20-byte recipient (empty binary for contract creation)
    - value_bytes: big-endian U256 value in wei
    - gas_limit: gas limit as integer
    - gas_price_bytes: big-endian U256 (gas_price or max_fee_per_gas)
    - max_priority_fee_bytes: big-endian U256 (empty for legacy/2930)
    - max_fee_per_blob_gas_bytes: big-endian U256 (empty unless EIP-4844)
    - input_data: calldata binary
    - tx_nonce: sender nonce as integer

    State:
    - state_data: binary-encoded pre-fetched account state
    - access_list_data: binary-encoded access list
    - blob_hashes_data: concatenated 32-byte blob versioned hashes
    - authorization_list_data: binary-encoded EIP-7702 authorization list
  """
  @spec execute_tx_v3(
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          binary(),
          binary()
        ) :: {:ok, map()} | {:error, atom() | binary()}
  def execute_tx_v3(
        _block_number,
        _block_timestamp,
        _coinbase,
        _base_fee,
        _prev_randao,
        _block_gas_limit,
        _excess_blob_gas,
        _tx_type,
        _from,
        _to,
        _value_bytes,
        _gas_limit,
        _gas_price_bytes,
        _max_priority_fee_bytes,
        _max_fee_per_blob_gas_bytes,
        _input_data,
        _tx_nonce,
        _state_data,
        _access_list_data,
        _blob_hashes_data,
        _authorization_list_data
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Executes a transaction with pre-loaded state (simplified version).

  Uses the state binary protocol to load accounts into the EVM database.
  Validation checks are disabled for testing flexibility.

  Parameters:
    - state_data: binary-encoded state (StateLoader protocol)
    - from: 20-byte sender address
    - to: 20-byte recipient (empty for contract creation)
    - value_bytes: 32-byte big-endian U256
    - gas_limit: gas limit as integer
    - gas_price_bytes: 32-byte big-endian U256
    - data: calldata binary
    - nonce: sender nonce as integer
  """
  @spec execute_tx_with_state(
          binary(),
          binary(),
          binary(),
          binary(),
          non_neg_integer(),
          binary(),
          binary(),
          non_neg_integer()
        ) :: {:ok, map()} | {:error, atom()}
  def execute_tx_with_state(
        _state_data,
        _from,
        _to,
        _value_bytes,
        _gas_limit,
        _gas_price_bytes,
        _data,
        _nonce
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  @doc "Returns the EVM engine version string."
  @spec evm_version() :: String.t()
  def evm_version, do: :erlang.nif_error(:nif_not_loaded)
end
