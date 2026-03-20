defmodule EthChain.ChainTest do
  use ExUnit.Case, async: true

  alias EthChain.Chain
  alias EthCore.Types.{Block, BlockHeader}

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
end
