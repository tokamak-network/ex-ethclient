defmodule EthVm.MainnetTxTest do
  @moduledoc """
  Integration test executing a known mainnet transaction via the real revm NIF.

  Uses mainnet block 46147 (the first block with a transaction).
  Transaction: 0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060

  This is a simple ETH transfer of 31337 wei from an EOA.
  Block 46147 is in the Frontier era (pre-Homestead).
  The gas price was 50 Gwei and gas limit 21000 (simple transfer).
  Expected gas_used: 21000.

  Tagged :nif so it only runs when the NIF is compiled.
  """

  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Native
  alias EthVm.StateLoader

  # Mainnet block 46147 - first block with a transaction
  # From: 0xa1e4380a3b1f749673e270229993ee55f35663b4
  # To:   0x5df9b87991262f6ba471f09758cde1c0fc1de734
  # Value: 31337 wei
  # Gas price: 50 Gwei (50_000_000_000)
  # Gas limit: 21000
  # Nonce: 0
  @from_addr Base.decode16!("A1E4380A3B1F749673E270229993EE55F35663B4", case: :upper)
  @to_addr Base.decode16!("5DF9B87991262F6BA471F09758CDE1C0FC1DE734", case: :upper)
  @value 31_337
  @gas_limit 21_000
  @gas_price 50_000_000_000
  @nonce 0

  # Block 46147 context (Frontier era)
  @block_number 46_147
  @block_timestamp 1_438_918_233
  @coinbase Base.decode16!("E6A7A1D47FF21B6321162AEA7C6CB457D5476BCA", case: :upper)
  @base_fee 0
  # Block 46147 gas limit was ~5,000,000 (miner-adjusted from genesis 5000)
  @block_gas_limit 5_000_000

  # Sender needs enough balance to cover value + gas * gas_price
  # 21000 * 50 Gwei = 1_050_000_000_000_000 wei + 31337 wei
  @sender_balance 10_000_000_000_000_000_000

  describe "mainnet block 46147 transaction via execute_tx_v3" do
    test "simple ETH transfer produces correct gas_used" do
      # Build pre-loaded state with sender balance
      accounts = %{
        @from_addr => %{
          nonce: @nonce,
          balance: @sender_balance,
          code: <<>>,
          storage: %{}
        },
        @to_addr => %{
          nonce: 0,
          balance: 0,
          code: <<>>,
          storage: %{}
        }
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_v3(
          @block_number,
          @block_timestamp,
          @coinbase,
          @base_fee,
          <<0::256>>,
          @block_gas_limit,
          0,
          # tx_type: Legacy
          0,
          @from_addr,
          @to_addr,
          :binary.encode_unsigned(@value, :big),
          @gas_limit,
          :binary.encode_unsigned(@gas_price, :big),
          # max_priority_fee (empty for legacy)
          <<>>,
          # max_fee_per_blob_gas (empty for legacy)
          <<>>,
          # input data (empty for transfer)
          <<>>,
          @nonce,
          state_binary,
          # access_list (empty for legacy)
          <<>>,
          # blob_hashes (empty for legacy)
          <<>>
        )

      assert {:ok, map} = result
      assert map[:success] == true
      # Simple ETH transfer costs exactly 21000 gas
      assert map[:gas_used] == 21_000
      assert is_map(map[:state_changes])
    end

    test "state_changes reflect sender debit and receiver credit" do
      accounts = %{
        @from_addr => %{
          nonce: @nonce,
          balance: @sender_balance,
          code: <<>>,
          storage: %{}
        },
        @to_addr => %{
          nonce: 0,
          balance: 0,
          code: <<>>,
          storage: %{}
        }
      }

      state_binary = StateLoader.serialize_state(accounts)

      {:ok, map} =
        Native.execute_tx_v3(
          @block_number,
          @block_timestamp,
          @coinbase,
          @base_fee,
          <<0::256>>,
          @block_gas_limit,
          0,
          0,
          @from_addr,
          @to_addr,
          :binary.encode_unsigned(@value, :big),
          @gas_limit,
          :binary.encode_unsigned(@gas_price, :big),
          <<>>,
          <<>>,
          <<>>,
          @nonce,
          state_binary,
          <<>>,
          <<>>
        )

      state_changes = map[:state_changes]

      # Sender should have nonce incremented
      sender_state = state_changes[@from_addr]
      assert sender_state != nil
      assert sender_state[:nonce] == @nonce + 1

      # Receiver should exist in state changes
      receiver_state = state_changes[@to_addr]
      assert receiver_state != nil
    end
  end

  describe "mainnet contract execution via execute_tx_v3" do
    test "contract bytecode executes and returns output" do
      # Simple contract: PUSH1 0x42, PUSH1 0x00, MSTORE, PUSH1 0x20, PUSH1 0x00, RETURN
      contract_code = <<0x60, 0x42, 0x60, 0x00, 0x52, 0x60, 0x20, 0x60, 0x00, 0xF3>>
      sender = <<0xAA::8, 0::152>>
      target = <<0xBB::8, 0::152>>

      accounts = %{
        sender => %{
          nonce: 0,
          balance: 10_000_000_000_000_000_000,
          code: <<>>,
          storage: %{}
        },
        target => %{
          nonce: 0,
          balance: 0,
          code: contract_code,
          storage: %{}
        }
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_v3(
          # block 15_000_000 (London era)
          15_000_000,
          1_660_000_000,
          <<0::160>>,
          # base_fee = 10 Gwei
          10_000_000_000,
          <<0::256>>,
          30_000_000,
          0,
          # tx_type: Legacy
          0,
          sender,
          target,
          <<>>,
          100_000,
          # gas_price = 20 Gwei
          :binary.encode_unsigned(20_000_000_000, :big),
          <<>>,
          <<>>,
          <<>>,
          0,
          state_binary,
          <<>>,
          <<>>
        )

      assert {:ok, map} = result
      assert map[:success] == true
      assert map[:gas_used] > 21_000
      # Output should be 32 bytes with 0x42 at the end
      assert byte_size(map[:output]) == 32
      assert :binary.at(map[:output], 31) == 0x42
    end
  end

  describe "error handling" do
    test "returns revert reason for reverting transaction" do
      # REVERT opcode: PUSH1 0x00 PUSH1 0x00 REVERT
      revert_code = <<0x60, 0x00, 0x60, 0x00, 0xFD>>
      sender = <<0xCC::8, 0::152>>
      target = <<0xDD::8, 0::152>>

      accounts = %{
        sender => %{
          nonce: 0,
          balance: 10_000_000_000_000_000_000,
          code: <<>>,
          storage: %{}
        },
        target => %{
          nonce: 0,
          balance: 0,
          code: revert_code,
          storage: %{}
        }
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_v3(
          15_000_000,
          1_660_000_000,
          <<0::160>>,
          10_000_000_000,
          <<0::256>>,
          30_000_000,
          0,
          0,
          sender,
          target,
          <<>>,
          100_000,
          :binary.encode_unsigned(20_000_000_000, :big),
          <<>>,
          <<>>,
          <<>>,
          0,
          state_binary,
          <<>>,
          <<>>
        )

      assert {:ok, map} = result
      assert map[:success] == false
      assert map[:gas_used] > 0
    end

    test "handles out of gas gracefully" do
      # PUSH1 loop that burns all gas: endless jumps
      # JUMPDEST PUSH1 0x00 JUMP (infinite loop)
      loop_code = <<0x5B, 0x60, 0x00, 0x56>>
      sender = <<0xEE::8, 0::152>>
      target = <<0xFF::8, 0::152>>

      accounts = %{
        sender => %{
          nonce: 0,
          balance: 10_000_000_000_000_000_000,
          code: <<>>,
          storage: %{}
        },
        target => %{
          nonce: 0,
          balance: 0,
          code: loop_code,
          storage: %{}
        }
      }

      state_binary = StateLoader.serialize_state(accounts)

      result =
        Native.execute_tx_v3(
          15_000_000,
          1_660_000_000,
          <<0::160>>,
          10_000_000_000,
          <<0::256>>,
          30_000_000,
          0,
          0,
          sender,
          target,
          <<>>,
          # Very low gas to force OOG
          22_000,
          :binary.encode_unsigned(20_000_000_000, :big),
          <<>>,
          <<>>,
          <<>>,
          0,
          state_binary,
          <<>>,
          <<>>
        )

      assert {:ok, map} = result
      assert map[:success] == false
    end
  end
end
