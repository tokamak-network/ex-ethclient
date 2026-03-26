defmodule EthChain.SystemOpsTest do
  use ExUnit.Case, async: true

  alias EthChain.SystemOps
  alias EthCore.Types.{BlockHeader, Log}

  @beacon_root <<0xAB::256>>
  @history_buffer_length 8191

  # Prague timestamp (mainnet activation)
  @prague_timestamp 1_740_434_200

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

  defp prague_header(opts \\ []) do
    make_header([timestamp: @prague_timestamp, number: 22_000_000] ++ opts)
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
      header =
        make_header(
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

  describe "post_block_system_calls/3 - pre-Prague" do
    test "returns state unchanged for Cancun fork" do
      header = make_header(timestamp: 1_710_338_200)
      state = %{foo: :bar}

      assert SystemOps.post_block_system_calls(header, state) == state
    end

    test "returns state unchanged for Cancun fork with receipts" do
      header = make_header(timestamp: 1_710_338_200)
      state = %{foo: :bar}

      assert SystemOps.post_block_system_calls(header, state, []) == state
    end
  end

  describe "post_block_system_calls/3 - EIP-6110 deposit requests" do
    test "extracts deposit events from receipts for Prague fork" do
      header = prague_header()

      # Build a mock deposit log with ABI-encoded data
      deposit_log =
        build_deposit_log(
          pubkey: :crypto.strong_rand_bytes(48),
          withdrawal_credentials: :crypto.strong_rand_bytes(32),
          amount: 32_000_000_000,
          signature: :crypto.strong_rand_bytes(96),
          index: 42
        )

      receipts = [%{logs: [deposit_log]}]
      state = SystemOps.post_block_system_calls(header, %{}, receipts)

      assert [deposit] = state[:deposit_requests]
      assert byte_size(deposit.pubkey) == 48
      assert byte_size(deposit.withdrawal_credentials) == 32
      assert deposit.amount == 32_000_000_000
      assert byte_size(deposit.signature) == 96
      assert deposit.index == 42
    end

    test "ignores non-deposit logs" do
      header = prague_header()

      other_log = %Log{
        address: :crypto.strong_rand_bytes(20),
        topics: [:crypto.strong_rand_bytes(32)],
        data: <<>>
      }

      receipts = [%{logs: [other_log]}]
      state = SystemOps.post_block_system_calls(header, %{}, receipts)

      assert state[:deposit_requests] == []
    end

    test "handles empty receipts" do
      header = prague_header()
      state = SystemOps.post_block_system_calls(header, %{}, [])

      assert state[:deposit_requests] == []
    end

    test "processes multiple deposits across multiple receipts" do
      header = prague_header()

      log1 =
        build_deposit_log(
          pubkey: :crypto.strong_rand_bytes(48),
          withdrawal_credentials: :crypto.strong_rand_bytes(32),
          amount: 32_000_000_000,
          signature: :crypto.strong_rand_bytes(96),
          index: 0
        )

      log2 =
        build_deposit_log(
          pubkey: :crypto.strong_rand_bytes(48),
          withdrawal_credentials: :crypto.strong_rand_bytes(32),
          amount: 64_000_000_000,
          signature: :crypto.strong_rand_bytes(96),
          index: 1
        )

      receipts = [%{logs: [log1]}, %{logs: [log2]}]
      state = SystemOps.post_block_system_calls(header, %{}, receipts)

      assert length(state[:deposit_requests]) == 2
      assert Enum.at(state[:deposit_requests], 0).index == 0
      assert Enum.at(state[:deposit_requests], 1).index == 1
    end
  end

  describe "post_block_system_calls/3 - EIP-7002 withdrawal requests" do
    test "returns empty withdrawal requests when queue is empty" do
      header = prague_header()
      state = SystemOps.post_block_system_calls(header, %{}, [])

      assert state[:withdrawal_requests] == []
    end

    test "dequeues withdrawal requests from contract storage" do
      header = prague_header()

      source_addr = :crypto.strong_rand_bytes(20)
      pubkey = :crypto.strong_rand_bytes(48)
      amount = <<0, 0, 0, 0, 0, 0, 0, 1>>

      # Build queue storage: head=0, tail=1, one 76-byte entry at slots 2,3,4
      withdrawal_addr = SystemOps.withdrawal_request_address()
      entry_data = source_addr <> pubkey <> amount
      storage = build_queue_storage(entry_data, 76, 0, 1)

      state = %{{:storage, withdrawal_addr} => storage}
      result = SystemOps.post_block_system_calls(header, state, [])

      assert [req] = result[:withdrawal_requests]
      assert req.source_address == source_addr
      assert req.validator_pubkey == pubkey
      assert req.amount == 1
    end

    test "drains queue after reading withdrawal requests" do
      header = prague_header()

      entry_data = :crypto.strong_rand_bytes(76)
      withdrawal_addr = SystemOps.withdrawal_request_address()
      storage = build_queue_storage(entry_data, 76, 0, 1)

      state = %{{:storage, withdrawal_addr} => storage}
      result = SystemOps.post_block_system_calls(header, state, [])

      # Head should now equal tail (queue drained)
      updated_storage = result[{:storage, withdrawal_addr}]
      assert Map.get(updated_storage, <<0::256>>) == <<1::256>>
    end
  end

  describe "post_block_system_calls/3 - EIP-7251 consolidation requests" do
    test "returns empty consolidation requests when queue is empty" do
      header = prague_header()
      state = SystemOps.post_block_system_calls(header, %{}, [])

      assert state[:consolidation_requests] == []
    end

    test "dequeues consolidation requests from contract storage" do
      header = prague_header()

      source_addr = :crypto.strong_rand_bytes(20)
      source_pubkey = :crypto.strong_rand_bytes(48)
      target_pubkey = :crypto.strong_rand_bytes(48)

      consolidation_addr = SystemOps.consolidation_request_address()
      entry_data = source_addr <> source_pubkey <> target_pubkey
      storage = build_queue_storage(entry_data, 116, 0, 1)

      state = %{{:storage, consolidation_addr} => storage}
      result = SystemOps.post_block_system_calls(header, state, [])

      assert [req] = result[:consolidation_requests]
      assert req.source_address == source_addr
      assert req.source_pubkey == source_pubkey
      assert req.target_pubkey == target_pubkey
    end

    test "drains queue after reading consolidation requests" do
      header = prague_header()

      entry_data = :crypto.strong_rand_bytes(116)
      consolidation_addr = SystemOps.consolidation_request_address()
      storage = build_queue_storage(entry_data, 116, 0, 1)

      state = %{{:storage, consolidation_addr} => storage}
      result = SystemOps.post_block_system_calls(header, state, [])

      updated_storage = result[{:storage, consolidation_addr}]
      assert Map.get(updated_storage, <<0::256>>) == <<1::256>>
    end
  end

  describe "address accessors" do
    test "beacon_root_address returns 20-byte address" do
      addr = SystemOps.beacon_root_address()
      assert byte_size(addr) == 20
    end

    test "deposit_contract_address returns 20-byte address" do
      addr = SystemOps.deposit_contract_address()
      assert byte_size(addr) == 20
      # 0x00000000219ab540356cBB839Cbe05303d7705Fa
      assert addr ==
               <<0x00, 0x00, 0x00, 0x00, 0x21, 0x9A, 0xB5, 0x40, 0x35, 0x6C, 0xBB, 0x83, 0x9C,
                 0xBE, 0x05, 0x30, 0x3D, 0x77, 0x05, 0xFA>>
    end

    test "withdrawal_request_address returns 20-byte address" do
      addr = SystemOps.withdrawal_request_address()
      assert byte_size(addr) == 20
      # 0x0c15F14308530b7CDB8460094BbB9cC28b9AAAb5
      assert addr ==
               <<0x0C, 0x15, 0xF1, 0x43, 0x08, 0x53, 0x0B, 0x7C, 0xDB, 0x84, 0x60, 0x09, 0x4B,
                 0xBB, 0x9C, 0xC2, 0x8B, 0x9A, 0xAA, 0xB5>>
    end

    test "consolidation_request_address returns 20-byte address" do
      addr = SystemOps.consolidation_request_address()
      assert byte_size(addr) == 20
      # 0x00431F263cE400f4da8Fc0D8c2d5488f877c1C36
      assert addr ==
               <<0x00, 0x43, 0x1F, 0x26, 0x3C, 0xE4, 0x00, 0xF4, 0xDA, 0x8F, 0xC0, 0xD8, 0xC2,
                 0xD5, 0x48, 0x8F, 0x87, 0x7C, 0x1C, 0x36>>
    end

    test "system_caller_address returns 20-byte address" do
      addr = SystemOps.system_caller_address()
      assert byte_size(addr) == 20
      # 0xfffffffffffffffffffffffffffffffffffffffe
      assert addr ==
               <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE>>
    end

    test "deposit_event_topic returns 32-byte hash" do
      topic = SystemOps.deposit_event_topic()
      assert byte_size(topic) == 32
    end
  end

  # Helpers

  # Build an ABI-encoded deposit log matching the deposit contract's DepositEvent.
  defp build_deposit_log(opts) do
    pubkey = Keyword.fetch!(opts, :pubkey)
    withdrawal_credentials = Keyword.fetch!(opts, :withdrawal_credentials)
    amount = Keyword.fetch!(opts, :amount)
    signature = Keyword.fetch!(opts, :signature)
    index = Keyword.fetch!(opts, :index)

    # ABI encode: 5 offsets + 5 (length + padded data) fields
    amount_bytes = <<amount::little-64>>
    index_bytes = <<index::little-64>>

    fields = [pubkey, withdrawal_credentials, amount_bytes, signature, index_bytes]

    # Calculate offsets: first field starts after 5 * 32 bytes of offsets
    {offsets, _} =
      Enum.map_reduce(fields, 5 * 32, fn field, offset ->
        padded = ceil_32(byte_size(field))
        {<<offset::unsigned-big-256>>, offset + 32 + padded}
      end)

    encoded_fields =
      Enum.map(fields, fn field ->
        len = byte_size(field)
        padded = ceil_32(len)
        padding_size = padded - len
        <<len::unsigned-big-256>> <> field <> <<0::size(padding_size * 8)>>
      end)

    data = IO.iodata_to_binary([offsets | encoded_fields])

    deposit_addr = SystemOps.deposit_contract_address()
    deposit_topic = SystemOps.deposit_event_topic()

    %Log{
      address: deposit_addr,
      topics: [deposit_topic],
      data: data
    }
  end

  defp ceil_32(n) do
    case rem(n, 32) do
      0 -> n
      r -> n + (32 - r)
    end
  end

  # Build a queue storage map for EIP-7002/7251 testing.
  # Stores one entry of `entry_size` bytes starting at slot 2, with head and tail pointers.
  defp build_queue_storage(entry_data, entry_size, head, tail) do
    entry_slots = ceil_32(entry_size) |> div(32)
    # Pad entry_data to fill complete slots
    padded = entry_data <> :binary.copy(<<0>>, entry_slots * 32 - entry_size)

    slot_pairs =
      for i <- 0..(entry_slots - 1)//1 do
        slot_key = <<2 + head * entry_slots + i::unsigned-big-256>>
        slot_value = binary_part(padded, i * 32, 32)
        {slot_key, slot_value}
      end

    Map.new([
      {<<0::256>>, <<head::unsigned-big-256>>},
      {<<1::256>>, <<tail::unsigned-big-256>>}
      | slot_pairs
    ])
  end
end
