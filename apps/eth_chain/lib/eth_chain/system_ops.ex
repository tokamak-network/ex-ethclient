defmodule EthChain.SystemOps do
  @moduledoc """
  Pre/post-block system operations.

  Implements system-level state changes that occur outside of normal
  transaction processing, such as storing the beacon block root
  per EIP-4788 (Cancun+).
  """

  alias EthChain.Fork
  alias EthCore.Types.BlockHeader

  @beacon_root_address <<0x00, 0x0F, 0x3D, 0xF6, 0xD7, 0x32, 0x80, 0x7E, 0xF1, 0x31,
                         0x70, 0x59, 0xDE, 0x73, 0x17, 0xE6, 0x94, 0x0E, 0x61, 0x13>>

  @history_buffer_length 8191

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

    if Fork.blob_transactions?(fork) and header.parent_beacon_block_root != nil do
      store_beacon_root(header, state)
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
    timestamp_idx = rem(header.timestamp, @history_buffer_length)
    root_idx = timestamp_idx + @history_buffer_length

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
