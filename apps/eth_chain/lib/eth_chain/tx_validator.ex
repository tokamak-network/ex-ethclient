defmodule EthChain.TxValidator do
  @moduledoc """
  Validates transactions for mempool admission and block execution.

  Performs pre-execution checks including signature recovery, chain ID
  verification, gas limit bounds, and EIP-1559 fee invariants.
  """

  alias EthChain.Gas
  alias EthCore.Transaction.Signer
  alias EthCore.Types.{SignedTransaction, Transaction}

  @doc """
  Validates a signed transaction for mempool admission.

  Checks:
  1. Recover sender address (verify signature is valid)
  2. Chain ID matches (if tx specifies one)
  3. Gas limit >= intrinsic gas
  4. Gas limit <= block gas limit (if provided)
  5. max_priority_fee_per_gas <= max_fee_per_gas (for EIP-1559+)
  """
  @spec validate_for_mempool(SignedTransaction.t(), keyword()) :: :ok | {:error, atom()}
  def validate_for_mempool(%SignedTransaction{} = signed_tx, opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id)
    block_gas_limit = Keyword.get(opts, :block_gas_limit)

    with :ok <- validate_signature(signed_tx),
         :ok <- validate_chain_id(signed_tx.tx, chain_id),
         :ok <- validate_intrinsic_gas(signed_tx),
         :ok <- validate_block_gas_limit(signed_tx.tx, block_gas_limit),
         :ok <- validate_fee_cap(signed_tx.tx) do
      :ok
    end
  end

  defp validate_signature(signed_tx) do
    case Signer.recover_sender(signed_tx) do
      {:ok, _sender} -> :ok
      {:error, _reason} -> {:error, :invalid_signature}
    end
  end

  defp validate_chain_id(_tx, nil), do: :ok

  defp validate_chain_id(%Transaction.Legacy{}, _chain_id), do: :ok

  defp validate_chain_id(tx, expected_chain_id) do
    tx_chain_id = tx_chain_id(tx)

    if tx_chain_id == expected_chain_id do
      :ok
    else
      {:error, :chain_id_mismatch}
    end
  end

  defp validate_intrinsic_gas(signed_tx) do
    intrinsic = Gas.intrinsic_gas(signed_tx)
    gas_limit = tx_gas_limit(signed_tx.tx)

    if gas_limit >= intrinsic do
      :ok
    else
      {:error, :gas_too_low}
    end
  end

  defp validate_block_gas_limit(_tx, nil), do: :ok

  defp validate_block_gas_limit(tx, block_gas_limit) do
    if tx_gas_limit(tx) <= block_gas_limit do
      :ok
    else
      {:error, :exceeds_block_gas_limit}
    end
  end

  defp validate_fee_cap(%Transaction.EIP1559{} = tx) do
    if tx.max_priority_fee_per_gas <= tx.max_fee_per_gas do
      :ok
    else
      {:error, :priority_fee_exceeds_max_fee}
    end
  end

  defp validate_fee_cap(%Transaction.EIP4844{} = tx) do
    if tx.max_priority_fee_per_gas <= tx.max_fee_per_gas do
      :ok
    else
      {:error, :priority_fee_exceeds_max_fee}
    end
  end

  defp validate_fee_cap(%Transaction.EIP7702{} = tx) do
    if tx.max_priority_fee_per_gas <= tx.max_fee_per_gas do
      :ok
    else
      {:error, :priority_fee_exceeds_max_fee}
    end
  end

  defp validate_fee_cap(_tx), do: :ok

  defp tx_chain_id(%Transaction.EIP2930{chain_id: id}), do: id
  defp tx_chain_id(%Transaction.EIP1559{chain_id: id}), do: id
  defp tx_chain_id(%Transaction.EIP4844{chain_id: id}), do: id
  defp tx_chain_id(%Transaction.EIP7702{chain_id: id}), do: id
  defp tx_chain_id(_tx), do: nil

  defp tx_gas_limit(%Transaction.Legacy{gas_limit: gl}), do: gl
  defp tx_gas_limit(%Transaction.EIP2930{gas_limit: gl}), do: gl
  defp tx_gas_limit(%Transaction.EIP1559{gas_limit: gl}), do: gl
  defp tx_gas_limit(%Transaction.EIP4844{gas_limit: gl}), do: gl
  defp tx_gas_limit(%Transaction.EIP7702{gas_limit: gl}), do: gl
end
