defmodule EthVm.Native do
  @moduledoc """
  Rust NIF bindings for EVM execution.

  Provides low-level access to the Rust-based EVM engine.
  Currently returns mock results; will be backed by revm in the future.
  """

  use Rustler,
    otp_app: :eth_vm,
    crate: "ethvm_native"

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

  @doc "Returns the EVM engine version string."
  @spec evm_version() :: String.t()
  def evm_version, do: :erlang.nif_error(:nif_not_loaded)
end
