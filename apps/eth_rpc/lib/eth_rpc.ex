defmodule EthRpc do
  @moduledoc """
  JSON-RPC 2.0 server for the Ethereum execution client.

  Provides an HTTP endpoint that handles eth_, net_, web3_, and engine_
  namespace methods following the Ethereum JSON-RPC specification.
  """

  @doc """
  Hello world.

  ## Examples

      iex> EthRpc.hello()
      :world

  """
  @spec hello() :: :world
  def hello do
    :world
  end
end
