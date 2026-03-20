defmodule EthChain.ChainTest do
  use ExUnit.Case, async: true

  alias EthChain.Chain
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}

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

  defp valid_block(parent \\ valid_parent()) do
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
      gas_used: 10_000_000,
      timestamp: parent.timestamp + 12,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000
    }

    %Block{header: header, transactions: [], ommers: []}
  end

  defp sample_tx do
    tx = %Transaction.Legacy{
      nonce: 0,
      gas_price: 2_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, 1, 1)
  end

  defp block_with_txs(parent, txs) do
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

  describe "validate_block/2" do
    test "accepts a valid block" do
      assert :ok == Chain.validate_block(valid_block(), valid_parent())
    end

    test "returns header validation errors" do
      block = valid_block()
      bad_header = %{block.header | number: 999}
      bad_block = %{block | header: bad_header}

      assert {:error, :invalid_block_number} ==
               Chain.validate_block(bad_block, valid_parent())
    end

    test "returns body validation errors" do
      block = valid_block()
      bad_block = %{block | ommers: [valid_parent()]}

      assert {:error, :non_empty_ommers} ==
               Chain.validate_block(bad_block, valid_parent())
    end
  end

  describe "process_block/3" do
    test "processes a valid block with Mock EVM" do
      parent = valid_parent()
      txs = [sample_tx()]
      block = block_with_txs(parent, txs)

      assert {:ok, result} = Chain.process_block(block, parent, evm: EthVm.Mock)
      assert result.gas_used == 21_000
      assert length(result.receipts) == 1
    end

    test "processes a valid empty block" do
      parent = valid_parent()
      block = block_with_txs(parent, [])

      assert {:ok, result} = Chain.process_block(block, parent)
      assert result.gas_used == 0
    end

    test "rejects block with invalid header" do
      parent = valid_parent()
      block = block_with_txs(parent, [])
      bad_header = %{block.header | number: 999}
      bad_block = %{block | header: bad_header}

      assert {:error, :invalid_block_number} = Chain.process_block(bad_block, parent)
    end

    test "rejects block with gas mismatch" do
      parent = valid_parent()
      txs = [sample_tx()]
      block = block_with_txs(parent, txs)
      # Set wrong gas_used
      bad_header = %{block.header | gas_used: 0}
      bad_block = %{block | header: bad_header}

      assert {:error, :gas_used_mismatch} = Chain.process_block(bad_block, parent)
    end
  end

  describe "build_block/5" do
    test "builds a block with no transactions" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      assert {:ok, block, result} = Chain.build_block(parent, coinbase, timestamp, [])
      assert block.header.number == 101
      assert block.header.coinbase == coinbase
      assert result.gas_used == 0
    end

    test "builds a block with transactions" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12
      txs = [sample_tx(), sample_tx()]

      assert {:ok, block, result} = Chain.build_block(parent, coinbase, timestamp, txs)
      assert block.header.gas_used == 42_000
      assert length(block.transactions) == 2
      assert result.gas_used == 42_000
    end
  end
end
