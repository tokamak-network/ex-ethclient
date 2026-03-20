defmodule EthStorage.AccountStore do
  @moduledoc "High-level API for account state operations."

  alias EthCore.Types.Account
  alias EthStorage.{Encoding, Store}

  @doc "Gets an account by address."
  @spec get_account(<<_::160>>, GenServer.server()) ::
          {:ok, Account.t() | nil} | {:error, term()}
  def get_account(address, store \\ Store) when byte_size(address) == 20 do
    address_hash = EthCrypto.Hash.keccak256(address)

    with {:ok, encoded} <- Store.get_account(store, address_hash) do
      if is_nil(encoded) do
        {:ok, nil}
      else
        Encoding.decode_account(encoded)
      end
    end
  end

  @doc "Stores an account by address."
  @spec put_account(<<_::160>>, Account.t(), GenServer.server()) ::
          :ok | {:error, term()}
  def put_account(address, %Account{} = account, store \\ Store)
      when byte_size(address) == 20 do
    address_hash = EthCrypto.Hash.keccak256(address)
    encoded = Encoding.encode_account(account)
    Store.put_account(store, address_hash, encoded)
  end

  @doc "Gets account bytecode by code hash."
  @spec get_code(<<_::256>>, GenServer.server()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_code(code_hash, store \\ Store) when byte_size(code_hash) == 32 do
    Store.get_account_code(store, code_hash)
  end

  @doc "Gets account storage value."
  @spec get_storage(<<_::160>>, <<_::256>>, GenServer.server()) ::
          {:ok, binary() | nil} | {:error, term()}
  def get_storage(address, slot_hash, store \\ Store)
      when byte_size(address) == 20 and byte_size(slot_hash) == 32 do
    key = EthCrypto.Hash.keccak256(address <> slot_hash)
    Store.get_storage_trie_node(store, key)
  end
end
