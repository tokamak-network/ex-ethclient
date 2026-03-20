defmodule EthStorage.Genesis do
  @moduledoc "Genesis block initialization for Ethereum mainnet."

  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{Encoding, Store}

  @zero_hash <<0::256>>
  @zero_address <<0::160>>

  # keccak256(RLP([])) — hash of empty uncle list
  @empty_ommers_hash Base.decode16!(
                       "1DCC4DE8DEC75D7AAB85B567B6CCD41AD312451B948A7413F0A142FD40D49347",
                       case: :upper
                     )

  # Empty trie root: keccak256(RLP(""))
  @empty_trie_root Base.decode16!(
                     "56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421",
                     case: :upper
                   )

  # Mainnet genesis state root
  @mainnet_state_root Base.decode16!(
                        "D7F8974FB5AC78D9AC099B9AD5018BEDC2CE0A72DAD1827A1709DA30580F0544",
                        case: :upper
                      )

  @mainnet_extra_data <<0x11, 0xBB, 0xE8, 0xDB, 0x4E, 0x34, 0x7B, 0x4E, 0x8C, 0x93, 0x7C, 0x1C,
                        0x83, 0x70, 0xE4, 0xB5, 0xED, 0x33, 0xAD, 0xB3, 0xDB, 0x69, 0xCB, 0xDB,
                        0x7A, 0x38, 0xE1, 0xE5, 0x0B, 0x1B, 0x82, 0xFA>>

  @mainnet_nonce <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x42>>

  @doc "Returns the mainnet genesis block header."
  @spec mainnet_header() :: BlockHeader.t()
  def mainnet_header do
    %BlockHeader{
      parent_hash: @zero_hash,
      ommers_hash: @empty_ommers_hash,
      coinbase: @zero_address,
      state_root: @mainnet_state_root,
      transactions_root: @empty_trie_root,
      receipts_root: @empty_trie_root,
      logs_bloom: <<0::2048>>,
      difficulty: 17_179_869_184,
      number: 0,
      gas_limit: 5000,
      gas_used: 0,
      timestamp: 0,
      extra_data: @mainnet_extra_data,
      mix_hash: @zero_hash,
      nonce: @mainnet_nonce
    }
  end

  @doc "Returns the mainnet genesis block."
  @spec mainnet_block() :: Block.t()
  def mainnet_block do
    %Block{
      header: mainnet_header(),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  @doc "Returns the hash of the mainnet genesis block."
  @spec mainnet_genesis_hash() :: <<_::256>>
  def mainnet_genesis_hash do
    Encoding.block_hash(mainnet_header())
  end

  @doc """
  Initializes the store with the genesis block.

  Stores the genesis header, body, canonical hash, and sets the latest
  block number to 0.
  """
  @spec initialize(GenServer.server()) :: :ok | {:error, term()}
  def initialize(store \\ Store) do
    block = mainnet_block()
    block_hash = Encoding.block_hash(block.header)
    encoded_header = Encoding.encode_header(block.header)
    encoded_body = Encoding.encode_body(block.transactions, block.ommers, block.withdrawals)

    with :ok <- Store.put_block_header(store, block_hash, encoded_header),
         :ok <- Store.put_block_body(store, block_hash, encoded_body),
         :ok <- Store.set_canonical_hash(store, 0, block_hash),
         :ok <- Store.set_latest_block_number(store, 0) do
      :ok
    end
  end
end
