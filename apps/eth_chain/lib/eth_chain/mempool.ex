defmodule EthChain.Mempool do
  @moduledoc """
  Transaction pool (mempool) as a GenServer.

  Stores pending transactions indexed by hash and sender address.
  Enforces a maximum pool size and provides sorted retrieval by gas price.
  """

  use GenServer

  alias EthCore.Types.{Block, SignedTransaction, Transaction}

  @max_pool_size 10_000

  # --- Client API ---

  @doc "Starts the mempool GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc """
  Adds a validated transaction to the pool.

  Returns `{:ok, tx_hash}` on success, or `{:error, reason}` if the pool
  is full or the transaction already exists.
  """
  @spec add_transaction(SignedTransaction.t(), GenServer.server()) ::
          {:ok, binary()} | {:error, atom()}
  def add_transaction(signed_tx, server \\ __MODULE__) do
    GenServer.call(server, {:add_transaction, signed_tx})
  end

  @doc "Removes a transaction by its hash."
  @spec remove_transaction(binary(), GenServer.server()) :: :ok
  def remove_transaction(tx_hash, server \\ __MODULE__) do
    GenServer.call(server, {:remove_transaction, tx_hash})
  end

  @doc """
  Returns pending transactions sorted by gas price in descending order.
  """
  @spec pending_transactions(GenServer.server()) :: [SignedTransaction.t()]
  def pending_transactions(server \\ __MODULE__) do
    GenServer.call(server, :pending_transactions)
  end

  @doc """
  Removes all transactions that were included in the given block.
  """
  @spec remove_block_transactions(Block.t(), GenServer.server()) :: :ok
  def remove_block_transactions(%Block{} = block, server \\ __MODULE__) do
    GenServer.call(server, {:remove_block_transactions, block})
  end

  @doc "Returns the current number of transactions in the pool."
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server \\ __MODULE__) do
    GenServer.call(server, :size)
  end

  # --- Server Callbacks ---

  @impl true
  def init(:ok) do
    state = %{
      transactions: %{},
      by_sender: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_transaction, signed_tx}, _from, state) do
    tx_hash = SignedTransaction.tx_hash(signed_tx)

    cond do
      Map.has_key?(state.transactions, tx_hash) ->
        {:reply, {:error, :already_exists}, state}

      map_size(state.transactions) >= @max_pool_size ->
        {:reply, {:error, :pool_full}, state}

      true ->
        sender = tx_sender_key(signed_tx)
        transactions = Map.put(state.transactions, tx_hash, signed_tx)

        by_sender =
          Map.update(state.by_sender, sender, [tx_hash], fn hashes ->
            [tx_hash | hashes]
          end)

        {:reply, {:ok, tx_hash}, %{state | transactions: transactions, by_sender: by_sender}}
    end
  end

  @impl true
  def handle_call({:remove_transaction, tx_hash}, _from, state) do
    state = do_remove_transaction(state, tx_hash)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:pending_transactions, _from, state) do
    txs =
      state.transactions
      |> Map.values()
      |> Enum.sort_by(&effective_gas_price/1, :desc)

    {:reply, txs, state}
  end

  @impl true
  def handle_call({:remove_block_transactions, block}, _from, state) do
    state =
      Enum.reduce(block.transactions, state, fn signed_tx, acc ->
        tx_hash = SignedTransaction.tx_hash(signed_tx)
        do_remove_transaction(acc, tx_hash)
      end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:size, _from, state) do
    {:reply, map_size(state.transactions), state}
  end

  # --- Private Helpers ---

  defp do_remove_transaction(state, tx_hash) do
    case Map.pop(state.transactions, tx_hash) do
      {nil, _transactions} ->
        state

      {signed_tx, transactions} ->
        sender = tx_sender_key(signed_tx)

        by_sender =
          case Map.get(state.by_sender, sender) do
            nil ->
              state.by_sender

            hashes ->
              remaining = List.delete(hashes, tx_hash)

              if remaining == [] do
                Map.delete(state.by_sender, sender)
              else
                Map.put(state.by_sender, sender, remaining)
              end
          end

        %{state | transactions: transactions, by_sender: by_sender}
    end
  end

  defp effective_gas_price(%SignedTransaction{tx: %Transaction.Legacy{gas_price: gp}}), do: gp
  defp effective_gas_price(%SignedTransaction{tx: %Transaction.EIP2930{gas_price: gp}}), do: gp

  defp effective_gas_price(%SignedTransaction{tx: %Transaction.EIP1559{max_fee_per_gas: mf}}),
    do: mf

  defp effective_gas_price(%SignedTransaction{tx: %Transaction.EIP4844{max_fee_per_gas: mf}}),
    do: mf

  defp effective_gas_price(%SignedTransaction{tx: %Transaction.EIP7702{max_fee_per_gas: mf}}),
    do: mf

  # Use the transaction nonce + type as a simple sender key proxy.
  # In a real implementation, this would recover the sender address from the signature.
  defp tx_sender_key(%SignedTransaction{tx: tx, v: v, r: r, s: s}) do
    :erlang.phash2({Transaction.type(tx), v, r, s})
  end
end
