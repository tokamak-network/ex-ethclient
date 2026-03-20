defmodule EthVm do
  @moduledoc """
  EVM execution engine for ex_ethclient.

  Provides a behaviour-based abstraction over EVM implementations,
  allowing pluggable backends (mock for testing, revm NIF for production).
  """
end
