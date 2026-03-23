defmodule EthChain.StateRoot do
  @moduledoc """
  Computes and verifies Ethereum state roots from account state.

  The state root is the root hash of the world state trie, where each
  account is stored at key = keccak256(address) with value =
  RLP([nonce, balance, storage_root, code_hash]).
  """

  alias EthChain.StorageTrie
  alias EthCore.Types.Account
  alias EthStorage.AccountRLP
  alias EthStorage.MPT.Trie

  @doc """
  Computes the state root hash from a map of address => Account.

  For each account:
  1. Key = keccak256(address)
  2. Value = RLP-encode([nonce, balance, storage_root, code_hash])
  3. Insert into MPT

  Returns the trie root hash.
  """
  @spec compute_state_root(%{binary() => Account.t()}) :: <<_::256>>
  def compute_state_root(accounts) when is_map(accounts) do
    trie =
      Enum.reduce(accounts, Trie.new(), fn {address, %Account{} = account}, acc ->
        key = EthCrypto.Hash.keccak256(address)
        value = AccountRLP.encode(account)
        Trie.put(acc, key, value)
      end)

    Trie.root_hash(trie)
  end

  @doc """
  Computes the storage root hash for an account's storage.

  For each storage slot:
  1. Key = keccak256(slot)
  2. Value = RLP-encode(value) with leading zeros stripped
  3. Insert into MPT

  Returns the trie root hash.
  """
  @spec compute_storage_root(%{binary() => binary()}) :: <<_::256>>
  def compute_storage_root(storage) when is_map(storage) do
    {_trie, root} = do_compute_storage_root(storage)
    root
  end

  @doc """
  Updates accounts with computed storage roots from their storage maps.

  For each account that has associated storage changes, computes the
  storage root and updates the account's storage_root field.
  """
  @spec update_storage_roots(
          %{binary() => Account.t()},
          %{binary() => %{binary() => binary()}}
        ) :: %{binary() => Account.t()}
  def update_storage_roots(accounts, storage_map) when is_map(accounts) and is_map(storage_map) do
    Enum.reduce(storage_map, accounts, fn {address, storage}, acc ->
      case Map.get(acc, address) do
        nil ->
          acc

        account ->
          new_root = compute_storage_root(storage)
          Map.put(acc, address, %{account | storage_root: new_root})
      end
    end)
  end

  @doc """
  Verifies that the expected state root matches the computed root
  from the given accounts.

  Returns :ok on match, {:error, :state_root_mismatch} otherwise.
  """
  @spec verify_state_root(binary(), %{binary() => Account.t()}) ::
          :ok | {:error, :state_root_mismatch}
  def verify_state_root(expected_root, accounts) when is_binary(expected_root) do
    computed = compute_state_root(accounts)

    if computed == expected_root do
      :ok
    else
      {:error, :state_root_mismatch}
    end
  end

  @spec do_compute_storage_root(%{binary() => binary()}) :: {Trie.t(), <<_::256>>}
  defp do_compute_storage_root(storage) do
    trie = StorageTrie.new()

    case StorageTrie.apply_storage_updates(trie, storage) do
      {:ok, updated_trie, root} -> {updated_trie, root}
    end
  end
end
