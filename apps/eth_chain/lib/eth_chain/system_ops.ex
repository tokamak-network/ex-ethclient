defmodule EthChain.SystemOps do
  @moduledoc """
  Pre/post-block system operations.

  Implements system-level state changes that occur outside of normal
  transaction processing, such as storing the beacon block root
  per EIP-4788 (Cancun+) and historical block hashes per EIP-2935 (Prague+).
  """

  alias EthChain.Fork
  alias EthCore.Types.BlockHeader

  @beacon_root_address <<0x00, 0x0F, 0x3D, 0xF6, 0xD7, 0x32, 0x80, 0x7E, 0xF1, 0x31,
                         0x70, 0x59, 0xDE, 0x73, 0x17, 0xE6, 0x94, 0x0E, 0x61, 0x13>>

  @beacon_root_buffer_length 8191

  # EIP-2935: Historical block hashes contract address
  @block_hash_history_address <<0x0F, 0x79, 0x2B, 0xE4, 0xB0, 0xC0, 0xCB, 0x4D, 0xAE, 0x44,
                                0x0E, 0xF1, 0x33, 0xE9, 0x0C, 0x0E, 0xCD, 0x48, 0xCC, 0xCC>>

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

  Currently a no-op. Reserved for future system operations.
  """
  @spec post_block_system_calls(BlockHeader.t(), map()) :: map()
  def post_block_system_calls(_header, state), do: state

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

  @spec encode_slot(non_neg_integer()) :: <<_::256>>
  defp encode_slot(value) do
    <<value::unsigned-big-256>>
  end
end
