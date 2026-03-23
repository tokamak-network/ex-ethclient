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

  @doc "Returns the EVM engine version string."
  @spec evm_version() :: String.t()
  def evm_version, do: :erlang.nif_error(:nif_not_loaded)
end
