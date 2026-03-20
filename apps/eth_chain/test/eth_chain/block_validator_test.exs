defmodule EthChain.BlockValidatorTest do
  use ExUnit.Case, async: true

  alias EthChain.BlockValidator
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

  defp valid_header(parent \\ valid_parent()) do
    %BlockHeader{
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
  end

  describe "validate_header/2" do
    test "accepts a valid post-merge header" do
      assert :ok == BlockValidator.validate_header(valid_header(), valid_parent())
    end

    test "rejects invalid block number (not parent + 1)" do
      header = %{valid_header() | number: 200}

      assert {:error, :invalid_block_number} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects block number equal to parent" do
      header = %{valid_header() | number: valid_parent().number}

      assert {:error, :invalid_block_number} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects timestamp not greater than parent" do
      header = %{valid_header() | timestamp: valid_parent().timestamp}

      assert {:error, :invalid_timestamp} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects timestamp less than parent" do
      header = %{valid_header() | timestamp: valid_parent().timestamp - 1}

      assert {:error, :invalid_timestamp} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects gas_used exceeding gas_limit" do
      header = %{valid_header() | gas_used: 30_000_001, gas_limit: 30_000_000}

      assert {:error, :gas_used_exceeds_limit} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "accepts gas_used equal to gas_limit" do
      header = %{valid_header() | gas_used: 30_000_000, gas_limit: 30_000_000}
      assert :ok == BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects gas_limit too high compared to parent" do
      # parent gas_limit is 30_000_000; bound is 30_000_000/1024 = 29296
      header = %{valid_header() | gas_limit: 30_030_000}

      assert {:error, :invalid_gas_limit} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects gas_limit too low compared to parent" do
      header = %{valid_header() | gas_limit: 29_970_000}

      assert {:error, :invalid_gas_limit} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects extra_data longer than 32 bytes" do
      header = %{valid_header() | extra_data: :binary.copy(<<1>>, 33)}

      assert {:error, :extra_data_too_long} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "accepts extra_data exactly 32 bytes" do
      header = %{valid_header() | extra_data: :binary.copy(<<1>>, 32)}
      assert :ok == BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects invalid ommers_hash (non-empty list hash)" do
      header = %{valid_header() | ommers_hash: <<0::256>>}

      assert {:error, :invalid_ommers_hash} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects non-zero difficulty (post-merge)" do
      header = %{valid_header() | difficulty: 1}

      assert {:error, :invalid_difficulty} ==
               BlockValidator.validate_header(header, valid_parent())
    end

    test "rejects non-zero nonce (post-merge)" do
      header = %{valid_header() | nonce: <<1, 0, 0, 0, 0, 0, 0, 0>>}
      assert {:error, :invalid_nonce} == BlockValidator.validate_header(header, valid_parent())
    end
  end

  describe "validate_body/1" do
    test "accepts block with empty ommers" do
      block = %Block{header: valid_header(), transactions: [], ommers: []}
      assert :ok == BlockValidator.validate_body(block)
    end

    test "rejects block with non-empty ommers" do
      block = %Block{header: valid_header(), transactions: [], ommers: [valid_parent()]}
      assert {:error, :non_empty_ommers} == BlockValidator.validate_body(block)
    end
  end
end
