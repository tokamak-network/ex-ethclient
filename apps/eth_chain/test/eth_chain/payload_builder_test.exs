defmodule EthChain.PayloadBuilderTest do
  use ExUnit.Case, async: true

  alias EthChain.PayloadBuilder
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

  defp sample_tx(gas_price \\ 2_000_000_000) do
    tx = %Transaction.Legacy{
      nonce: 0,
      gas_price: gas_price,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, 1, 1)
  end

  defp sample_eip1559_tx(max_fee) do
    tx = %Transaction.EIP1559{
      chain_id: 1,
      nonce: 0,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: max_fee,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>,
      access_list: []
    }

    SignedTransaction.new(tx, 0, 1, 1)
  end

  describe "build_payload/6" do
    test "builds a block with no transactions" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      assert {:ok, %Block{} = block, result} =
               PayloadBuilder.build_payload(parent, coinbase, timestamp, [], EthVm.Mock, nil)

      assert block.header.number == 101
      assert block.header.coinbase == coinbase
      assert block.header.timestamp == timestamp
      assert block.header.gas_used == 0
      assert block.transactions == []
      assert result.gas_used == 0
    end

    test "builds a block with transactions using Mock EVM" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12
      txs = [sample_tx(), sample_tx()]

      assert {:ok, %Block{} = block, result} =
               PayloadBuilder.build_payload(
                 parent,
                 coinbase,
                 timestamp,
                 txs,
                 EthVm.Mock,
                 nil
               )

      assert block.header.number == 101
      assert block.header.gas_used == 42_000
      assert length(block.transactions) == 2
      assert result.gas_used == 42_000
      assert length(result.receipts) == 2
    end

    test "filters transactions below base fee" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      # Parent: gas_used=15M, gas_limit=30M, base_fee=1B
      # Target=15M, gas_used==target, so next base_fee stays 1_000_000_000
      low_fee_tx = sample_tx(100)
      high_fee_tx = sample_tx(2_000_000_000)

      assert {:ok, block, _result} =
               PayloadBuilder.build_payload(
                 parent,
                 coinbase,
                 timestamp,
                 [low_fee_tx, high_fee_tx],
                 EthVm.Mock,
                 nil
               )

      # Only the high fee tx should be included
      assert length(block.transactions) == 1
    end

    test "filters EIP-1559 transactions below base fee" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      low_fee_tx = sample_eip1559_tx(100)
      high_fee_tx = sample_eip1559_tx(2_000_000_000)

      assert {:ok, block, _result} =
               PayloadBuilder.build_payload(
                 parent,
                 coinbase,
                 timestamp,
                 [low_fee_tx, high_fee_tx],
                 EthVm.Mock,
                 nil
               )

      assert length(block.transactions) == 1
    end

    test "sets correct base_fee_per_gas in block header" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      assert {:ok, block, _result} =
               PayloadBuilder.build_payload(parent, coinbase, timestamp, [], EthVm.Mock, nil)

      # Parent: gas_used=15M, gas_limit=30M, target=15M -> base fee unchanged
      assert block.header.base_fee_per_gas == 1_000_000_000
    end

    test "inherits gas_limit from parent" do
      parent = valid_parent()
      coinbase = <<42::160>>
      timestamp = parent.timestamp + 12

      assert {:ok, block, _result} =
               PayloadBuilder.build_payload(parent, coinbase, timestamp, [], EthVm.Mock, nil)

      assert block.header.gas_limit == parent.gas_limit
    end
  end
end
