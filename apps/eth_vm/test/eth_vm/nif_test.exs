defmodule EthVm.NifTest do
  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Nif
  alias EthVm.Types.{BlockExecutionResult, Environment, ExecutionResult}

  defp mock_env do
    %Environment{
      coinbase: <<0::160>>,
      gas_limit: 30_000_000,
      number: 1,
      timestamp: 1_700_000_000
    }
  end

  defp mock_signed_tx do
    tx = %EthCore.Types.Transaction.Legacy{
      nonce: 0,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      # Use address > 0x09 to avoid precompile addresses
      to: <<0xBB::8, 0::152>>,
      value: 1_000_000_000_000_000_000,
      data: <<>>
    }

    %EthCore.Types.SignedTransaction{tx: tx, v: 27, r: 1, s: 1}
  end

  defp mock_block(txs \\ []) do
    header = %EthCore.Types.BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 1,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_700_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }

    %EthCore.Types.Block{header: header, transactions: txs}
  end

  describe "execute_transaction/3" do
    test "returns successful execution result for simple transfer" do
      assert {:ok, %ExecutionResult{} = result} =
               Nif.execute_transaction(mock_env(), mock_signed_tx(), :ignored)

      assert result.success == true
      assert result.gas_used == 21_000
      assert result.gas_refunded == 0
      assert result.output == <<>>
      assert result.logs == []
      assert result.error == nil
    end
  end

  describe "execute_block/2" do
    test "returns empty result for block with no transactions" do
      assert {:ok, %BlockExecutionResult{} = result} =
               Nif.execute_block(mock_block(), :ignored)

      assert result.receipts == []
      assert result.gas_used == 0
      assert result.account_updates == %{}
      assert result.logs == []
    end

    test "returns receipts for each transaction" do
      txs = [mock_signed_tx(), mock_signed_tx(), mock_signed_tx()]

      assert {:ok, %BlockExecutionResult{} = result} =
               Nif.execute_block(mock_block(txs), :ignored)

      assert length(result.receipts) == 3
      assert result.gas_used == 63_000

      [r1, r2, r3] = result.receipts
      assert r1.cumulative_gas_used == 21_000
      assert r2.cumulative_gas_used == 42_000
      assert r3.cumulative_gas_used == 63_000

      Enum.each(result.receipts, fn receipt ->
        assert receipt.status == 1
        assert receipt.type == 0
        assert receipt.logs == []
      end)
    end
  end
end
