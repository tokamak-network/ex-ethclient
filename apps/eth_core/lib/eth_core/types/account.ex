defmodule EthCore.Types.Account do
  @empty_code_hash EthCrypto.Hash.keccak256("")

  @empty_trie_hash EthCrypto.Hash.keccak256(<<0x80>>)

  defstruct nonce: 0,
            balance: 0,
            storage_root: @empty_trie_hash,
            code_hash: @empty_code_hash

  @type t :: %__MODULE__{
          nonce: non_neg_integer(),
          balance: non_neg_integer(),
          storage_root: <<_::256>>,
          code_hash: <<_::256>>
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      nonce: Keyword.get(opts, :nonce, 0),
      balance: Keyword.get(opts, :balance, 0),
      storage_root: Keyword.get(opts, :storage_root, @empty_trie_hash),
      code_hash: Keyword.get(opts, :code_hash, @empty_code_hash)
    }
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{nonce: 0, balance: 0, code_hash: code_hash}) do
    code_hash == @empty_code_hash
  end

  def empty?(_), do: false

  @spec has_code?(t()) :: boolean()
  def has_code?(%__MODULE__{code_hash: code_hash}) do
    code_hash != @empty_code_hash
  end
end
