defmodule EthChain.TxPipeline do
  @moduledoc "Processes incoming transactions from RPC or peers."

  alias EthChain.{Mempool, TxValidator}
  alias EthCore.RLP
  alias EthCore.Types.SignedTransaction

  @doc """
  Processes a raw transaction received via eth_sendRawTransaction.

  1. Decode the RLP-encoded signed transaction
  2. Validate for mempool admission
  3. Add to mempool
  4. Return tx hash
  """
  @spec submit_transaction(binary(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def submit_transaction(raw_tx, opts \\ []) when is_binary(raw_tx) do
    mempool = Keyword.get(opts, :mempool, Mempool)
    validator_opts = Keyword.get(opts, :validator_opts, [])

    with {:ok, signed_tx} <- decode_transaction(raw_tx),
         :ok <- TxValidator.validate_for_mempool(signed_tx, validator_opts),
         {:ok, tx_hash} <- Mempool.add_transaction(signed_tx, mempool) do
      {:ok, tx_hash}
    end
  end

  @doc """
  Processes transactions received from a peer.

  Validates each transaction and adds valid ones to the mempool.
  Invalid transactions are silently dropped.
  """
  @spec process_peer_transactions([SignedTransaction.t()], keyword()) :: :ok
  def process_peer_transactions(transactions, opts \\ []) do
    mempool = Keyword.get(opts, :mempool, Mempool)
    validator_opts = Keyword.get(opts, :validator_opts, [])

    Enum.each(transactions, fn signed_tx ->
      with :ok <- TxValidator.validate_for_mempool(signed_tx, validator_opts),
           {:ok, _hash} <- Mempool.add_transaction(signed_tx, mempool) do
        :ok
      else
        _error -> :ok
      end
    end)
  end

  @spec decode_transaction(binary()) ::
          {:ok, SignedTransaction.t()} | {:error, term()}
  defp decode_transaction(raw_tx) do
    case RLP.decode_signed(raw_tx) do
      {:ok, _signed_tx} = ok -> ok
      {:error, _} = err -> err
    end
  end
end
