defmodule EthChain.SystemOps do
  @moduledoc """
  Pre/post-block system operations.

  Implements system-level state changes that occur outside of normal
  transaction processing, such as storing the beacon block root
  per EIP-4788 (Cancun+), historical block hashes per EIP-2935 (Prague+),
  and post-block request processing for Prague system EIPs:

  - EIP-6110: Deposit contract event parsing
  - EIP-7002: Execution layer triggerable withdrawal requests
  - EIP-7251: Consolidation requests
  """

  alias EthChain.Fork
  alias EthCore.Types.{BlockHeader, Log}

  @beacon_root_address <<0x00, 0x0F, 0x3D, 0xF6, 0xD7, 0x32, 0x80, 0x7E, 0xF1, 0x31, 0x70, 0x59,
                         0xDE, 0x73, 0x17, 0xE6, 0x94, 0x0E, 0x61, 0x13>>

  @beacon_root_buffer_length 8191

  # EIP-2935: Historical block hashes contract address
  @block_hash_history_address <<0x0F, 0x79, 0x2B, 0xE4, 0xB0, 0xC0, 0xCB, 0x4D, 0xAE, 0x44, 0x0E,
                                0xF1, 0x33, 0xE9, 0x0C, 0x0E, 0xCD, 0x48, 0xCC, 0xCC>>

  # EIP-6110: Deposit contract address (Beacon deposit contract on mainnet)
  @deposit_contract_address <<0x00, 0x00, 0x00, 0x00, 0x21, 0x9A, 0xB5, 0x40, 0x35, 0x6C, 0xBB,
                              0x83, 0x9C, 0xBE, 0x05, 0x30, 0x3D, 0x77, 0x05, 0xFA>>

  # EIP-6110: DepositEvent topic (keccak256 of DepositEvent signature)
  # DepositEvent(bytes pubkey, bytes withdrawal_credentials, bytes amount, bytes signature, bytes index)
  @deposit_event_topic <<0x64, 0x9B, 0xBC, 0x62, 0xD0, 0xE3, 0x19, 0x42, 0xBF, 0xD2, 0x36, 0x1B,
                         0x94, 0x2C, 0xE4, 0x15, 0x17, 0x77, 0x39, 0x5E, 0x7A, 0xC0, 0xDA, 0x2C,
                         0xB7, 0xA7, 0xB0, 0xBB, 0xEC, 0x39, 0x21, 0x95>>

  # EIP-7002: Withdrawal request contract address
  @withdrawal_request_address <<0x0C, 0x15, 0xF1, 0x43, 0x08, 0x53, 0x0B, 0x7C, 0xDB, 0x84, 0x60,
                                0x09, 0x4B, 0xBB, 0x9C, 0xC2, 0x8B, 0x9A, 0xAA, 0xB5>>

  # EIP-7251: Consolidation request contract address
  @consolidation_request_address <<0x00, 0x43, 0x1F, 0x26, 0x3C, 0xE4, 0x00, 0xF4, 0xDA, 0x8F,
                                   0xC0, 0xD8, 0xC2, 0xD5, 0x48, 0x8F, 0x87, 0x7C, 0x1C, 0x36>>

  # System caller address used for EIP-7002 and EIP-7251 system calls
  @system_caller_address <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                           0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE>>

  # EIP-7002/7251: Storage slot 0 holds the queue head pointer
  @queue_head_slot <<0::unsigned-big-256>>
  # EIP-7002/7251: Storage slot 1 holds the queue tail pointer
  @queue_tail_slot <<1::unsigned-big-256>>
  # EIP-7002/7251: Queue data starts at storage slot 2
  @queue_data_start 2

  # EIP-2935: Ring buffer stores the last 8192 block hashes
  @block_hash_history_buffer_length 8192

  @doc """
  Returns the beacon root contract address (EIP-4788).
  """
  @spec beacon_root_address() :: <<_::160>>
  def beacon_root_address, do: @beacon_root_address

  @doc """
  Executes pre-block system calls.

  For Cancun+ forks, stores the parent_beacon_block_root in the beacon
  root contract storage per EIP-4788:
  1. timestamp_idx = timestamp mod 8191
  2. Store parent_beacon_block_root at slot timestamp_idx
  3. Store timestamp at slot (timestamp_idx + 8191)

  Returns updated state map with contract storage changes.
  """
  @spec pre_block_system_calls(BlockHeader.t(), map()) :: map()
  def pre_block_system_calls(%BlockHeader{} = header, state) do
    fork = Fork.active_fork(header.number, header.timestamp)

    state =
      if Fork.blob_transactions?(fork) and header.parent_beacon_block_root != nil do
        store_beacon_root(header, state)
      else
        state
      end

    if Fork.prague?(fork) and header.number > 0 do
      store_block_hash_history(header, state)
    else
      state
    end
  end

  @doc """
  Executes post-block system calls.

  For Prague+ forks, processes three system EIPs that produce execution requests:
  - EIP-6110: Parses deposit events from transaction receipts
  - EIP-7002: Reads queued withdrawal requests from the withdrawal request contract
  - EIP-7251: Reads queued consolidation requests from the consolidation request contract

  Returns an updated state map containing any request data under `:requests` keys.
  """
  @spec post_block_system_calls(BlockHeader.t(), map(), [map()]) :: map()
  def post_block_system_calls(header, state, receipts \\ []) do
    fork = Fork.active_fork(header.number, header.timestamp)

    if Fork.prague?(fork) do
      state
      |> process_deposit_requests(receipts)
      |> process_withdrawal_requests()
      |> process_consolidation_requests()
    else
      state
    end
  end

  @spec store_beacon_root(BlockHeader.t(), map()) :: map()
  defp store_beacon_root(header, state) do
    timestamp_idx = rem(header.timestamp, @beacon_root_buffer_length)
    root_idx = timestamp_idx + @beacon_root_buffer_length

    timestamp_slot = encode_slot(timestamp_idx)
    root_slot = encode_slot(root_idx)

    timestamp_value = encode_slot(header.timestamp)
    root_value = header.parent_beacon_block_root

    # Get or create beacon root contract account storage
    contract_storage = get_contract_storage(state, @beacon_root_address)

    updated_storage =
      contract_storage
      |> Map.put(timestamp_slot, timestamp_value)
      |> Map.put(root_slot, root_value)

    put_contract_storage(state, @beacon_root_address, updated_storage)
  end

  @doc """
  Returns the block hash history contract address (EIP-2935).
  """
  @spec block_hash_history_address() :: <<_::160>>
  def block_hash_history_address, do: @block_hash_history_address

  @doc """
  Returns the deposit contract address (EIP-6110).
  """
  @spec deposit_contract_address() :: <<_::160>>
  def deposit_contract_address, do: @deposit_contract_address

  @doc """
  Returns the deposit event topic hash (EIP-6110).
  """
  @spec deposit_event_topic() :: <<_::256>>
  def deposit_event_topic, do: @deposit_event_topic

  @doc """
  Returns the withdrawal request contract address (EIP-7002).
  """
  @spec withdrawal_request_address() :: <<_::160>>
  def withdrawal_request_address, do: @withdrawal_request_address

  @doc """
  Returns the consolidation request contract address (EIP-7251).
  """
  @spec consolidation_request_address() :: <<_::160>>
  def consolidation_request_address, do: @consolidation_request_address

  @doc """
  Returns the system caller address used for EIP-7002 and EIP-7251 system calls.
  """
  @spec system_caller_address() :: <<_::160>>
  def system_caller_address, do: @system_caller_address

  # EIP-2935: Store parent block hash in the history contract.
  # The contract uses a ring buffer of 8192 slots indexed by (block_number % 8192).
  @spec store_block_hash_history(BlockHeader.t(), map()) :: map()
  defp store_block_hash_history(header, state) do
    parent_number = header.number - 1
    slot_idx = rem(parent_number, @block_hash_history_buffer_length)
    slot_key = encode_slot(slot_idx)

    contract_storage = get_contract_storage(state, @block_hash_history_address)
    updated_storage = Map.put(contract_storage, slot_key, header.parent_hash)

    put_contract_storage(state, @block_hash_history_address, updated_storage)
  end

  @spec get_contract_storage(map(), binary()) :: %{binary() => binary()}
  defp get_contract_storage(state, address) do
    case Map.get(state, {:storage, address}) do
      nil -> %{}
      storage -> storage
    end
  end

  @spec put_contract_storage(map(), binary(), %{binary() => binary()}) :: map()
  defp put_contract_storage(state, address, storage) do
    Map.put(state, {:storage, address}, storage)
  end

  # EIP-6110: Parse deposit events from transaction receipts.
  # Scans all receipt logs for DepositEvent emissions from the deposit contract,
  # then extracts (pubkey, withdrawal_credentials, amount, signature, index) from log data.
  @spec process_deposit_requests(map(), [map()]) :: map()
  defp process_deposit_requests(state, receipts) do
    deposits =
      receipts
      |> Enum.flat_map(fn receipt -> Map.get(receipt, :logs, []) end)
      |> Enum.filter(&deposit_log?/1)
      |> Enum.map(&parse_deposit_log/1)

    Map.put(state, :deposit_requests, deposits)
  end

  @spec deposit_log?(Log.t()) :: boolean()
  defp deposit_log?(%Log{address: address, topics: [topic | _]}) do
    address == @deposit_contract_address and topic == @deposit_event_topic
  end

  defp deposit_log?(_), do: false

  # Parses the ABI-encoded DepositEvent log data.
  # The deposit contract emits data as concatenated SSZ-encoded fields with
  # ABI offset/length wrappers. The actual field data layout (after ABI decoding):
  #   - pubkey: 48 bytes
  #   - withdrawal_credentials: 32 bytes
  #   - amount: 8 bytes (little-endian)
  #   - signature: 96 bytes
  #   - index: 8 bytes (little-endian)
  @spec parse_deposit_log(Log.t()) :: map()
  defp parse_deposit_log(%Log{data: data}) do
    # ABI encoding: 5 dynamic fields, each prefixed by 32-byte offset then 32-byte length.
    # Offsets are at positions 0..4 (5 * 32 = 160 bytes of offsets).
    # Each field: 32-byte length prefix + padded data.
    <<_offsets::binary-size(160), rest::binary>> = data

    {pubkey, rest} = decode_abi_bytes(rest)
    {withdrawal_credentials, rest} = decode_abi_bytes(rest)
    {amount_bytes, rest} = decode_abi_bytes(rest)
    {signature, rest} = decode_abi_bytes(rest)
    {index_bytes, _rest} = decode_abi_bytes(rest)

    %{
      pubkey: pubkey,
      withdrawal_credentials: withdrawal_credentials,
      amount: :binary.decode_unsigned(amount_bytes, :little),
      signature: signature,
      index: :binary.decode_unsigned(index_bytes, :little)
    }
  end

  # Decodes a single ABI dynamic bytes field: 32-byte length + ceil(length/32)*32 data bytes.
  @spec decode_abi_bytes(binary()) :: {binary(), binary()}
  defp decode_abi_bytes(<<length::unsigned-big-256, rest::binary>>) do
    padded_length = ceil_to_32(length)

    <<value::binary-size(length), _padding::binary-size(padded_length - length), rest2::binary>> =
      rest

    {value, rest2}
  end

  @spec ceil_to_32(non_neg_integer()) :: non_neg_integer()
  defp ceil_to_32(n) do
    case rem(n, 32) do
      0 -> n
      r -> n + (32 - r)
    end
  end

  # EIP-7002: Read queued withdrawal requests from the withdrawal request contract.
  # The system caller triggers the contract to dequeue pending withdrawal requests.
  # In our storage-based approach, we read the queue from contract storage slots:
  #   slot 0 = queue head, slot 1 = queue tail, slot 2+ = queue data.
  # Each withdrawal request is 76 bytes: 20 (source address) + 48 (validator pubkey) + 8 (amount).
  @spec process_withdrawal_requests(map()) :: map()
  defp process_withdrawal_requests(state) do
    {requests, state} = dequeue_requests(state, @withdrawal_request_address, 76)

    withdrawal_requests =
      Enum.map(requests, fn <<source::binary-size(20), pubkey::binary-size(48),
                              amount::binary-size(8)>> ->
        %{
          source_address: source,
          validator_pubkey: pubkey,
          amount: :binary.decode_unsigned(amount, :big)
        }
      end)

    # Record the system call in state (system caller touched the contract)
    state =
      put_contract_storage(
        state,
        @withdrawal_request_address,
        get_contract_storage(state, @withdrawal_request_address)
        |> Map.put(encode_slot(0xFF_FF), encode_slot(1))
      )

    Map.put(state, :withdrawal_requests, withdrawal_requests)
  end

  # EIP-7251: Read queued consolidation requests from the consolidation contract.
  # Similar queue structure to EIP-7002.
  # Each consolidation request is 116 bytes: 20 (source) + 48 (source pubkey) + 48 (target pubkey).
  @spec process_consolidation_requests(map()) :: map()
  defp process_consolidation_requests(state) do
    {requests, state} = dequeue_requests(state, @consolidation_request_address, 116)

    consolidation_requests =
      Enum.map(requests, fn
        <<source::binary-size(20), source_pubkey::binary-size(48),
          target_pubkey::binary-size(48)>> ->
          %{
            source_address: source,
            source_pubkey: source_pubkey,
            target_pubkey: target_pubkey
          }
      end)

    # Record the system call in state
    state =
      put_contract_storage(
        state,
        @consolidation_request_address,
        get_contract_storage(state, @consolidation_request_address)
        |> Map.put(encode_slot(0xFF_FF), encode_slot(1))
      )

    Map.put(state, :consolidation_requests, consolidation_requests)
  end

  # Reads queued request entries from a system contract's storage.
  # Queue structure: slot 0 = head pointer, slot 1 = tail pointer, slot 2+ = data.
  # Each entry is `entry_size` bytes, stored contiguously starting from
  # slot (@queue_data_start + head * entry_slots) where entry_slots = ceil(entry_size / 32).
  # After reading, updates head to match tail (drains the queue).
  @spec dequeue_requests(map(), binary(), pos_integer()) :: {[binary()], map()}
  defp dequeue_requests(state, contract_address, entry_size) do
    storage = get_contract_storage(state, contract_address)
    head = decode_slot_value(Map.get(storage, @queue_head_slot, <<0::256>>))
    tail = decode_slot_value(Map.get(storage, @queue_tail_slot, <<0::256>>))

    if head >= tail do
      {[], state}
    else
      entry_slots = ceil_to_32(entry_size) |> div(32)

      entries =
        Enum.map(head..(tail - 1)//1, fn idx ->
          base_slot = @queue_data_start + idx * entry_slots

          slot_data =
            Enum.map(0..(entry_slots - 1)//1, fn offset ->
              slot_key = encode_slot(base_slot + offset)
              Map.get(storage, slot_key, <<0::256>>)
            end)

          slot_data
          |> IO.iodata_to_binary()
          |> binary_part(0, entry_size)
        end)

      # Drain the queue: set head = tail
      updated_storage = Map.put(storage, @queue_head_slot, encode_slot(tail))
      state = put_contract_storage(state, contract_address, updated_storage)

      {entries, state}
    end
  end

  @spec decode_slot_value(<<_::256>>) :: non_neg_integer()
  defp decode_slot_value(<<value::unsigned-big-256>>), do: value

  @spec encode_slot(non_neg_integer()) :: <<_::256>>
  defp encode_slot(value) do
    <<value::unsigned-big-256>>
  end
end
