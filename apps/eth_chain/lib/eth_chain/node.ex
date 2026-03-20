defmodule EthChain.Node do
  @moduledoc "Coordinates full Ethereum node components."

  alias EthStorage.{BlockStore, Genesis, Store}

  @doc """
  Initializes the node.

  1. Initialize storage with genesis block (if not already initialized)
  2. Return current chain head info
  """
  @spec initialize(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def initialize(store) do
    with :ok <- ensure_genesis(store),
         {:ok, head} <- chain_head(store) do
      {:ok, head}
    end
  end

  @doc "Returns the current chain head."
  @spec chain_head(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def chain_head(store) do
    case BlockStore.latest_block_number(store) do
      {:ok, nil} ->
        {:ok, %{head_number: 0, head_hash: <<0::256>>}}

      {:ok, number} ->
        case Store.get_canonical_hash(store, number) do
          {:ok, nil} ->
            {:ok, %{head_number: number, head_hash: <<0::256>>}}

          {:ok, hash} ->
            {:ok, %{head_number: number, head_hash: hash}}

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  @spec ensure_genesis(GenServer.server()) :: :ok | {:error, term()}
  defp ensure_genesis(store) do
    case BlockStore.latest_block_number(store) do
      {:ok, nil} -> Genesis.initialize(store)
      {:ok, _number} -> :ok
      {:error, _} = err -> err
    end
  end
end
