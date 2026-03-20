defmodule EthStorage do
  @moduledoc """
  Ethereum storage layer for blocks, state, and trie data.

  Provides a pluggable backend architecture with a high-level Store API
  and a Merkle Patricia Trie implementation for state root computation.
  """

  @doc "Returns the default store process name."
  @spec store_name() :: atom()
  def store_name, do: EthStorage.Store
end
