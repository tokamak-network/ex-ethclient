defmodule EthChain.StorageTrie do
  @moduledoc """
  Manages per-account storage tries.

  Each Ethereum account has its own storage trie that maps 256-bit keys
  to RLP-encoded values. Storage keys are hashed with Keccak-256 before
  insertion (secure trie).
  """

  alias EthStorage.MPT.Trie

  @doc "Creates a new empty storage trie."
  @spec new() :: Trie.t()
  def new, do: Trie.new()

  @doc """
  Applies storage updates to an account's storage trie.
  Returns the updated trie and new storage root hash.

  Keys are hashed with Keccak-256 before insertion. Values are
  RLP-encoded before storage. Zero-value entries are deleted.
  """
  @spec apply_storage_updates(Trie.t(), %{binary() => binary()}) ::
          {:ok, Trie.t(), <<_::256>>}
  def apply_storage_updates(%Trie{} = trie, storage_updates)
      when is_map(storage_updates) do
    updated_trie =
      Enum.reduce(storage_updates, trie, fn {key, value}, acc ->
        hashed_key = EthCrypto.Hash.keccak256(key)
        encoded_value = ExRLP.encode(value)

        if zero_value?(value) do
          Trie.delete(acc, hashed_key)
        else
          Trie.put(acc, hashed_key, encoded_value)
        end
      end)

    {:ok, updated_trie, Trie.root_hash(updated_trie)}
  end

  @doc "Gets a storage value from the trie."
  @spec get_storage(Trie.t(), binary()) :: {:ok, binary() | nil}
  def get_storage(%Trie{} = trie, key) when is_binary(key) do
    hashed_key = EthCrypto.Hash.keccak256(key)

    case Trie.get(trie, hashed_key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, encoded} -> {:ok, ExRLP.decode(encoded)}
    end
  end

  @spec zero_value?(binary()) :: boolean()
  defp zero_value?(<<>>), do: true

  defp zero_value?(bin) when is_binary(bin) do
    bin == :binary.copy(<<0>>, byte_size(bin))
  end
end
