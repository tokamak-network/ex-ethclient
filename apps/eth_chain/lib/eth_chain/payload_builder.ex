defmodule EthChain.PayloadBuilder do
  @moduledoc """
  Builds block payloads from pending mempool transactions.

  Assembles new blocks by selecting transactions, computing header fields
  (base fee, gas limit), and executing the block through the EVM.
  """

  alias EthChain.BaseFee
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthVm.Types.BlockExecutionResult

  @doc """
  Builds a new block on top of the given parent header.

  Selects transactions, computes header fields, executes through the EVM,
  and returns the finalized block with its execution result.

  Steps:
  1. Calculate next base fee from parent
  2. Calculate gas limit (same as parent for now)
  3. Filter transactions by base fee
  4. Build block header with computed fields
  5. Create block with selected transactions
  6. Execute via EVM
  7. Fill in gas_used from execution result
  8. Return block + execution result
  """
  @spec build_payload(
          BlockHeader.t(),
          <<_::160>>,
          non_neg_integer(),
          [SignedTransaction.t()],
          module(),
          module()
        ) :: {:ok, Block.t(), BlockExecutionResult.t()} | {:error, term()}
  def build_payload(
        %BlockHeader{} = parent_header,
        coinbase,
        timestamp,
        transactions,
        evm_module,
        state_provider
      ) do
    base_fee = next_base_fee(parent_header)
    gas_limit = parent_header.gas_limit

    filtered_txs = filter_by_base_fee(transactions, base_fee)

    header = build_header(parent_header, coinbase, timestamp, gas_limit, base_fee)
    block = %Block{header: header, transactions: filtered_txs, ommers: []}

    with {:ok, result} <- evm_module.execute_block(block, state_provider) do
      final_header = %{header | gas_used: result.gas_used}
      final_block = %{block | header: final_header}
      {:ok, final_block, result}
    end
  end

  defp next_base_fee(%BlockHeader{base_fee_per_gas: nil}), do: 0

  defp next_base_fee(%BlockHeader{} = parent) do
    BaseFee.calc_next_base_fee(
      parent.gas_used,
      parent.gas_limit,
      parent.base_fee_per_gas
    )
  end

  defp filter_by_base_fee(transactions, base_fee) do
    Enum.filter(transactions, fn %SignedTransaction{tx: tx} ->
      effective_max_fee(tx) >= base_fee
    end)
  end

  defp effective_max_fee(%Transaction.Legacy{gas_price: gp}), do: gp
  defp effective_max_fee(%Transaction.EIP2930{gas_price: gp}), do: gp
  defp effective_max_fee(%Transaction.EIP1559{max_fee_per_gas: mf}), do: mf
  defp effective_max_fee(%Transaction.EIP4844{max_fee_per_gas: mf}), do: mf
  defp effective_max_fee(%Transaction.EIP7702{max_fee_per_gas: mf}), do: mf

  defp build_header(parent, coinbase, timestamp, gas_limit, base_fee) do
    empty_ommers_hash = EthCrypto.Hash.keccak256(ExRLP.encode([]))

    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: empty_ommers_hash,
      coinbase: coinbase,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: parent.number + 1,
      gas_limit: gas_limit,
      gas_used: 0,
      timestamp: timestamp,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: base_fee
    }
  end
end
