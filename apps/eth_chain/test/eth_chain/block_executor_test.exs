defmodule EthChain.BlockExecutorTest do
  use ExUnit.Case, async: true

  alias EthChain.BlockExecutor
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthVm.Types.Environment

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  defp valid_parent do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 100,
      gas_limit: 30_000_000,
      gas_used: 15_000_000,
      timestamp: 1_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000
    }
  end

  defp valid_block_with_txs(parent, txs) do
    # Mock EVM uses 21_000 gas per tx
    gas_used = length(txs) * 21_000

    header = %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: parent.number + 1,
      gas_limit: 30_000_000,
      gas_used: gas_used,
      timestamp: parent.timestamp + 12,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000
    }

    %Block{header: header, transactions: txs, ommers: []}
  end

  defp sample_tx do
    tx = %Transaction.Legacy{
      nonce: 0,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, 1, 1)
  end

  describe "execute_block/4" do
    test "executes a valid block with no transactions" do
      parent = valid_parent()
      block = valid_block_with_txs(parent, [])

      assert {:ok, result} = BlockExecutor.execute_block(block, parent, EthVm.Mock, nil)
      assert result.gas_used == 0
      assert result.receipts == []
    end

    test "executes a valid block with transactions using Mock EVM" do
      parent = valid_parent()
      txs = [sample_tx(), sample_tx()]
      block = valid_block_with_txs(parent, txs)

      assert {:ok, result} = BlockExecutor.execute_block(block, parent, EthVm.Mock, nil)
      assert result.gas_used == 42_000
      assert length(result.receipts) == 2
    end

    test "fails when header gas_used does not match execution result" do
      parent = valid_parent()
      txs = [sample_tx()]
      block = valid_block_with_txs(parent, txs)
      # Override gas_used to wrong value
      bad_header = %{block.header | gas_used: 99_999}
      bad_block = %{block | header: bad_header}

      assert {:error, :gas_used_mismatch} =
               BlockExecutor.execute_block(bad_block, parent, EthVm.Mock, nil)
    end

    test "fails on invalid block number" do
      parent = valid_parent()
      block = valid_block_with_txs(parent, [])
      bad_header = %{block.header | number: 999}
      bad_block = %{block | header: bad_header}

      assert {:error, :invalid_block_number} =
               BlockExecutor.execute_block(bad_block, parent, EthVm.Mock, nil)
    end

    test "fails on non-empty ommers" do
      parent = valid_parent()
      block = valid_block_with_txs(parent, [])
      bad_block = %{block | ommers: [parent]}

      assert {:error, :non_empty_ommers} =
               BlockExecutor.execute_block(bad_block, parent, EthVm.Mock, nil)
    end
  end

  describe "build_environment/1" do
    test "maps header fields to environment" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<42::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 101,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: 1_000_012,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: 875_000_000
      }

      env = BlockExecutor.build_environment(header)

      assert %Environment{} = env
      assert env.coinbase == <<42::160>>
      assert env.gas_limit == 30_000_000
      assert env.number == 101
      assert env.timestamp == 1_000_012
      assert env.difficulty == 0
      assert env.base_fee_per_gas == 875_000_000
      assert env.chain_id == 1
    end

    test "defaults base_fee_per_gas to 0 when nil" do
      header = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 1,
        gas_limit: 30_000_000,
        gas_used: 0,
        timestamp: 100,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>,
        base_fee_per_gas: nil
      }

      env = BlockExecutor.build_environment(header)
      assert env.base_fee_per_gas == 0
    end
  end
end
