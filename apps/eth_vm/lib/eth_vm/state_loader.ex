defmodule EthVm.StateLoader do
  @moduledoc """
  Loads account state from EthStorage into a compact binary format
  suitable for consumption by the Rust NIF.

  The binary protocol is designed to be simple and fast to parse in Rust:

  - 4 bytes: num_accounts (big-endian u32)
  - Per account:
    - 20 bytes: address
    - 8 bytes: nonce (big-endian u64)
    - 32 bytes: balance (big-endian U256)
    - 4 bytes: code_length (big-endian u32)
    - N bytes: code
    - 4 bytes: num_storage_slots (big-endian u32)
    - Per slot: 32 bytes key + 32 bytes value
  """

  alias EthStorage.AccountStore

  @type account_info :: %{
          nonce: non_neg_integer(),
          balance: non_neg_integer(),
          code: binary(),
          storage: %{binary() => binary()}
        }

  @type accounts_map :: %{binary() => account_info()}

  @doc """
  Loads transaction-relevant state from the store and serializes it
  into the NIF binary protocol.

  Collects all addresses referenced by the transaction (from, to,
  access list), fetches their account data from storage, and returns
  the serialized binary.
  """
  @spec load_tx_state(map(), GenServer.server()) :: {:ok, binary()} | {:error, term()}
  def load_tx_state(tx_info, store) do
    addresses = collect_addresses(tx_info)

    with {:ok, accounts_map} <- fetch_accounts(addresses, store) do
      {:ok, serialize_state(accounts_map)}
    end
  end

  @doc """
  Extracts all unique addresses referenced by a transaction.

  Includes the sender (from), recipient (to), and any addresses
  in the access list.
  """
  @spec collect_addresses(map()) :: MapSet.t(binary())
  def collect_addresses(tx_info) do
    addresses = MapSet.new()

    # Add from address
    addresses =
      case Map.get(tx_info, :from) do
        addr when is_binary(addr) and byte_size(addr) == 20 -> MapSet.put(addresses, addr)
        _ -> addresses
      end

    # Add to address
    addresses =
      case Map.get(tx_info, :to) do
        addr when is_binary(addr) and byte_size(addr) == 20 -> MapSet.put(addresses, addr)
        _ -> addresses
      end

    # Add access list addresses
    access_list = Map.get(tx_info, :access_list, [])
    add_access_list_addresses(addresses, access_list)
  end

  @doc """
  Serializes an accounts map into the NIF binary protocol.

  The map should have 20-byte address keys and account_info values
  containing nonce, balance, code, and storage.
  """
  @spec serialize_state(accounts_map()) :: binary()
  def serialize_state(accounts_map) when is_map(accounts_map) do
    num_accounts = map_size(accounts_map)
    header = <<num_accounts::unsigned-big-32>>

    accounts_binary =
      Enum.reduce(accounts_map, <<>>, fn {address, info}, acc ->
        acc <> serialize_account(address, info)
      end)

    header <> accounts_binary
  end

  # --- Private Functions ---

  @spec add_access_list_addresses(MapSet.t(binary()), list()) :: MapSet.t(binary())
  defp add_access_list_addresses(addresses, access_list) when is_list(access_list) do
    Enum.reduce(access_list, addresses, fn
      {addr, _storage_keys}, acc when is_binary(addr) and byte_size(addr) == 20 ->
        MapSet.put(acc, addr)

      %{address: addr}, acc when is_binary(addr) and byte_size(addr) == 20 ->
        MapSet.put(acc, addr)

      _, acc ->
        acc
    end)
  end

  defp add_access_list_addresses(addresses, _), do: addresses

  @spec fetch_accounts(MapSet.t(binary()), GenServer.server()) ::
          {:ok, accounts_map()} | {:error, term()}
  defp fetch_accounts(addresses, store) do
    Enum.reduce_while(addresses, {:ok, %{}}, fn address, {:ok, acc} ->
      case fetch_single_account(address, store) do
        {:ok, info} -> {:cont, {:ok, Map.put(acc, address, info)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec fetch_single_account(binary(), GenServer.server()) ::
          {:ok, account_info()} | {:error, term()}
  defp fetch_single_account(address, store) do
    with {:ok, account} <- AccountStore.get_account(address, store) do
      case account do
        nil ->
          {:ok, %{nonce: 0, balance: 0, code: <<>>, storage: %{}}}

        account ->
          code = fetch_code(account.code_hash, store)

          {:ok,
           %{
             nonce: account.nonce,
             balance: account.balance,
             code: code,
             storage: %{}
           }}
      end
    end
  end

  @spec fetch_code(binary(), GenServer.server()) :: binary()
  defp fetch_code(code_hash, store) do
    empty_code_hash = EthCore.Types.Account.empty_code_hash()

    if code_hash == empty_code_hash do
      <<>>
    else
      case AccountStore.get_code(code_hash, store) do
        {:ok, code} when is_binary(code) -> code
        _ -> <<>>
      end
    end
  end

  @spec serialize_account(binary(), account_info()) :: binary()
  defp serialize_account(address, info) when byte_size(address) == 20 do
    nonce = Map.get(info, :nonce, 0)
    balance = Map.get(info, :balance, 0)
    code = Map.get(info, :code, <<>>)
    storage = Map.get(info, :storage, %{})

    balance_bytes = encode_u256(balance)
    code_length = byte_size(code)
    num_slots = map_size(storage)

    storage_binary =
      Enum.reduce(storage, <<>>, fn {key, value}, acc ->
        acc <> pad_to_32(key) <> pad_to_32(value)
      end)

    address <>
      <<nonce::unsigned-big-64>> <>
      balance_bytes <>
      <<code_length::unsigned-big-32>> <>
      code <>
      <<num_slots::unsigned-big-32>> <>
      storage_binary
  end

  @spec encode_u256(non_neg_integer()) :: <<_::256>>
  defp encode_u256(value) when is_integer(value) and value >= 0 do
    <<value::unsigned-big-256>>
  end

  @spec pad_to_32(binary()) :: <<_::256>>
  defp pad_to_32(bin) when byte_size(bin) >= 32 do
    binary_part(bin, byte_size(bin) - 32, 32)
  end

  defp pad_to_32(bin) do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8)>> <> bin
  end
end
