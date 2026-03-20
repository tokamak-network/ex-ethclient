defmodule EthChain.StateManager do
  @moduledoc """
  Manages world state transitions using MPT.

  Applies account updates from block execution to the state trie,
  computing new state roots after each transition. Uses Keccak-256
  hashed addresses as keys (secure trie).
  """

  alias EthChain.StorageTrie
  alias EthCore.Types.Account
  alias EthStorage.{AccountRLP, Store}
  alias EthStorage.MPT.Trie

  @doc """
  Applies account updates from block execution to the state trie.
  Returns the updated trie and new state root hash.

  Steps for each account update:
  1. Get existing account (or create new empty account)
  2. Update nonce and balance
  3. If code changed: store code in store, update code_hash
  4. If storage changed: update storage trie, compute new storage_root
  5. RLP-encode the account and put into state trie
  6. Return new state root
  """
  @spec apply_account_updates(Trie.t(), %{binary() => map()}, GenServer.server()) ::
          {:ok, Trie.t(), <<_::256>>} | {:error, term()}
  def apply_account_updates(%Trie{} = trie, account_updates, store)
      when is_map(account_updates) do
    result =
      Enum.reduce_while(account_updates, {:ok, trie}, fn {address, update}, {:ok, acc_trie} ->
        case apply_account_update(acc_trie, address, update, store) do
          {:ok, new_trie} -> {:cont, {:ok, new_trie}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, final_trie} -> {:ok, final_trie, state_root(final_trie)}
      {:error, _} = err -> err
    end
  end

  @doc "Gets an account from the state trie."
  @spec get_account(Trie.t(), binary()) :: {:ok, Account.t() | nil}
  def get_account(%Trie{} = trie, address) when is_binary(address) do
    key = EthCrypto.Hash.keccak256(address)

    case Trie.get(trie, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, encoded} -> AccountRLP.decode(encoded)
    end
  end

  @doc """
  Applies a single account update to the state trie.

  Creates a new account if one does not exist at the address.
  Updates nonce, balance, code, and storage as specified.
  """
  @spec apply_account_update(Trie.t(), binary(), map(), GenServer.server()) ::
          {:ok, Trie.t()} | {:error, term()}
  def apply_account_update(%Trie{} = trie, address, update, store)
      when is_binary(address) and is_map(update) do
    key = EthCrypto.Hash.keccak256(address)

    with {:ok, existing} <- get_account(trie, address) do
      account = existing || Account.new()
      account = update_nonce_and_balance(account, update)

      with {:ok, account} <- maybe_update_code(account, update, store),
           {:ok, account} <- maybe_update_storage(account, update) do
        encoded = AccountRLP.encode(account)
        {:ok, Trie.put(trie, key, encoded)}
      end
    end
  end

  @doc "Computes the state root from a trie."
  @spec state_root(Trie.t()) :: <<_::256>>
  def state_root(%Trie{} = trie), do: Trie.root_hash(trie)

  @spec update_nonce_and_balance(Account.t(), map()) :: Account.t()
  defp update_nonce_and_balance(account, update) do
    account
    |> maybe_set(:nonce, update)
    |> maybe_set(:balance, update)
  end

  @spec maybe_set(Account.t(), atom(), map()) :: Account.t()
  defp maybe_set(account, field, update) do
    case Map.fetch(update, field) do
      {:ok, value} -> Map.put(account, field, value)
      :error -> account
    end
  end

  @spec maybe_update_code(Account.t(), map(), GenServer.server()) ::
          {:ok, Account.t()} | {:error, term()}
  defp maybe_update_code(account, %{code: code}, store)
       when is_binary(code) and byte_size(code) > 0 do
    code_hash = EthCrypto.Hash.keccak256(code)

    case Store.put_account_code(store, code_hash, code) do
      :ok -> {:ok, %{account | code_hash: code_hash}}
      {:error, _} = err -> err
    end
  end

  defp maybe_update_code(account, _update, _store), do: {:ok, account}

  @spec maybe_update_storage(Account.t(), map()) ::
          {:ok, Account.t()} | {:error, term()}
  defp maybe_update_storage(account, %{storage: storage})
       when is_map(storage) and map_size(storage) > 0 do
    storage_trie = StorageTrie.new()

    case StorageTrie.apply_storage_updates(storage_trie, storage) do
      {:ok, _trie, new_root} ->
        {:ok, %{account | storage_root: new_root}}
    end
  end

  defp maybe_update_storage(account, _update), do: {:ok, account}
end
