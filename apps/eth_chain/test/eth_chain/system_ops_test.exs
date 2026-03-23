defmodule EthChain.SystemOpsTest do
  use ExUnit.Case, async: true

  alias EthChain.SystemOps
  alias EthCore.Types.BlockHeader

  @beacon_root <<0xAB::256>>
  @history_buffer_length 8191

  defp make_header(opts \\ []) do
    defaults = %{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 20_000_000,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_710_338_200,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000,
      parent_beacon_block_root: @beacon_root
    }

    struct!(BlockHeader, Map.merge(defaults, Map.new(opts)))
  end

  describe "pre_block_system_calls/2" do
    test "stores beacon root at correct slot for Cancun+ fork" do
      header = make_header(timestamp: 1_710_338_200)
      state = SystemOps.pre_block_system_calls(header, %{})

      beacon_addr = SystemOps.beacon_root_address()
      storage = Map.get(state, {:storage, beacon_addr})

      assert storage != nil

      timestamp_idx = rem(1_710_338_200, @history_buffer_length)
      root_idx = timestamp_idx + @history_buffer_length

      timestamp_slot = <<timestamp_idx::unsigned-big-256>>
      root_slot = <<root_idx::unsigned-big-256>>

      assert Map.get(storage, timestamp_slot) == <<1_710_338_200::unsigned-big-256>>
      assert Map.get(storage, root_slot) == @beacon_root
    end

    test "non-Cancun fork returns state unchanged" do
      # Use a pre-Cancun timestamp (Shanghai era)
      header = make_header(
        timestamp: 1_681_338_500,
        number: 17_000_000,
        parent_beacon_block_root: nil
      )

      state = %{some: :data}
      result = SystemOps.pre_block_system_calls(header, state)

      assert result == state
    end

    test "returns state unchanged when parent_beacon_block_root is nil" do
      header = make_header(parent_beacon_block_root: nil)
      state = %{some: :data}
      result = SystemOps.pre_block_system_calls(header, state)

      assert result == state
    end
  end

  describe "post_block_system_calls/2" do
    test "returns state unchanged (no-op)" do
      header = make_header()
      state = %{foo: :bar}

      assert SystemOps.post_block_system_calls(header, state) == state
    end
  end

  describe "beacon_root_address/0" do
    test "returns 20-byte address" do
      addr = SystemOps.beacon_root_address()
      assert byte_size(addr) == 20
    end
  end
end
