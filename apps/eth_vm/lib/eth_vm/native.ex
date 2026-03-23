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
  Executes a transaction with pre-loaded world state.

  The state_data binary contains serialized account state produced by
  `EthVm.StateLoader.serialize_state/1`.
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
        ) :: {:ok, map()} | {:error, atom() | String.t()}
  def execute_tx_with_state(
        _state_data,
        _from,
        _to,
        _value,
        _gas_limit,
        _gas_price,
        _data,
        _nonce
      ),
      do: :erlang.nif_error(:nif_not_loaded)

  @doc "Returns the EVM engine version string."
  @spec evm_version() :: String.t()
  def evm_version, do: :erlang.nif_error(:nif_not_loaded)
end
