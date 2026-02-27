defmodule EthCore.Types.Account do
  @moduledoc """
  Ethereum account state as stored in the world state trie.
  """

  alias EthCore.Types.Hash

  @type t :: %__MODULE__{
          nonce: non_neg_integer(),
          balance: non_neg_integer(),
          storage_root: Hash.t(),
          code_hash: Hash.t()
        }

  @empty_trie_root Base.decode16!(
                     "56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421",
                     case: :upper
                   )
  @empty_code_hash Base.decode16!(
                     "C5D2460186F7233C927E7DB2DCc703C0E500B653CA82273B7BFAD8045D85A470",
                     case: :mixed
                   )

  defstruct nonce: 0,
            balance: 0,
            storage_root: @empty_trie_root,
            code_hash: @empty_code_hash

  @doc "Creates a new empty account."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Creates a new account with the given balance."
  @spec new(non_neg_integer()) :: t()
  def new(balance) when is_integer(balance) and balance >= 0 do
    %__MODULE__{balance: balance}
  end

  @doc "Returns the empty trie root hash."
  @spec empty_trie_root() :: Hash.t()
  def empty_trie_root, do: @empty_trie_root

  @doc "Returns the empty code hash (keccak256 of empty bytes)."
  @spec empty_code_hash() :: Hash.t()
  def empty_code_hash, do: @empty_code_hash

  @doc "Checks if the account is empty per EIP-161."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{nonce: 0, balance: 0, code_hash: code_hash}) do
    code_hash == @empty_code_hash
  end

  def empty?(_), do: false
end
