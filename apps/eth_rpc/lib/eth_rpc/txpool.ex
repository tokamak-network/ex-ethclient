defmodule EthRpc.Txpool do
  @moduledoc """
  Implements txpool_ RPC namespace methods.

  Provides inspection into the transaction pool (mempool) state,
  including pending and queued transactions.
  """

  alias EthChain.Mempool
  alias EthCore.Types.{SignedTransaction, Transaction}
  alias EthRpc.Hex

  @doc """
  Returns the full content of the transaction pool.

  Groups transactions by status (pending/queued) and by sender address.
  Each transaction is formatted as a JSON-RPC transaction object.
  """
  @spec content(list()) :: {:ok, map()}
  def content(_params) do
    if mempool_available?() do
      txs = Mempool.pending_transactions()
      pending = group_transactions(txs)
      {:ok, %{"pending" => pending, "queued" => %{}}}
    else
      {:ok, %{"pending" => %{}, "queued" => %{}}}
    end
  end

  @doc """
  Returns the number of pending and queued transactions in the pool.

  Returns hex-encoded counts for each category.
  """
  @spec status(list()) :: {:ok, map()}
  def status(_params) do
    if mempool_available?() do
      count = Mempool.size()
      {:ok, %{"pending" => Hex.encode_quantity(count), "queued" => "0x0"}}
    else
      {:ok, %{"pending" => "0x0", "queued" => "0x0"}}
    end
  end

  # -- Private helpers -------------------------------------------------------

  @spec mempool_available?() :: boolean()
  defp mempool_available? do
    pid = GenServer.whereis(Mempool)
    is_pid(pid) and Process.alive?(pid)
  end

  @spec group_transactions([SignedTransaction.t()]) :: map()
  defp group_transactions(txs) do
    txs
    |> Enum.group_by(&tx_sender_hex/1)
    |> Enum.into(%{}, fn {sender, sender_txs} ->
      tx_map =
        Enum.into(sender_txs, %{}, fn signed_tx ->
          nonce_str = Integer.to_string(tx_nonce(signed_tx.tx))

          formatted = %{
            "hash" => Hex.encode_data(SignedTransaction.tx_hash(signed_tx)),
            "nonce" => Hex.encode_quantity(tx_nonce(signed_tx.tx)),
            "value" => Hex.encode_quantity(tx_value(signed_tx.tx)),
            "gas" => Hex.encode_quantity(tx_gas_limit(signed_tx.tx)),
            "input" => Hex.encode_data(tx_data(signed_tx.tx))
          }

          {nonce_str, formatted}
        end)

      {sender, tx_map}
    end)
  end

  @spec tx_sender_hex(SignedTransaction.t()) :: String.t()
  defp tx_sender_hex(signed_tx) do
    case EthCore.Transaction.Signer.recover_sender(signed_tx) do
      {:ok, address} -> Hex.encode_data(address)
      {:error, _} -> "0x" <> String.duplicate("0", 40)
    end
  end

  defp tx_nonce(%Transaction.Legacy{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP2930{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP1559{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP4844{nonce: n}), do: n
  defp tx_nonce(%Transaction.EIP7702{nonce: n}), do: n

  defp tx_value(%Transaction.Legacy{value: v}), do: v
  defp tx_value(%Transaction.EIP2930{value: v}), do: v
  defp tx_value(%Transaction.EIP1559{value: v}), do: v
  defp tx_value(%Transaction.EIP4844{value: v}), do: v
  defp tx_value(%Transaction.EIP7702{value: v}), do: v

  defp tx_gas_limit(%Transaction.Legacy{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP2930{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP1559{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP4844{gas_limit: g}), do: g
  defp tx_gas_limit(%Transaction.EIP7702{gas_limit: g}), do: g

  defp tx_data(%Transaction.Legacy{data: d}), do: d || <<>>
  defp tx_data(%Transaction.EIP2930{data: d}), do: d || <<>>
  defp tx_data(%Transaction.EIP1559{data: d}), do: d || <<>>
  defp tx_data(%Transaction.EIP4844{data: d}), do: d || <<>>
  defp tx_data(%Transaction.EIP7702{data: d}), do: d || <<>>
end
