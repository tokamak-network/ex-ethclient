defmodule EthStorage.Genesis do
  @moduledoc "Genesis block initialization for Ethereum mainnet, Sepolia, and Holesky testnets."

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

  # Sepolia genesis state root (empty state — Sepolia uses a pre-funded genesis)
  @sepolia_state_root Base.decode16!(
                        "5EB6E371A698B8D68F665192350FFCECBBBF322916F4B51BD79BB6887DA3F494",
                        case: :upper
                      )

  @sepolia_extra_data <<0x53, 0x65, 0x70, 0x6F, 0x6C, 0x69, 0x61, 0x2C, 0x20, 0x41, 0x74, 0x68,
                        0x65, 0x6E, 0x73, 0x2C, 0x20, 0x41, 0x74, 0x74, 0x69, 0x63, 0x61, 0x2C,
                        0x20, 0x47, 0x72, 0x65, 0x65, 0x63, 0x65, 0x21>>

  # Holesky genesis state root
  @holesky_state_root Base.decode16!(
                        "69D8C9D72F6FA4AD42D4702B433707212F90DB395EB54DC20BC85DE253788783",
                        case: :upper
                      )

  # "Holesky" in hex
  @holesky_extra_data <<0x48, 0x6F, 0x6C, 0x65, 0x73, 0x6B, 0x79>>

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

  @doc "Returns the Sepolia genesis block header."
  @spec sepolia_header() :: BlockHeader.t()
  def sepolia_header do
    %BlockHeader{
      parent_hash: @zero_hash,
      ommers_hash: @empty_ommers_hash,
      coinbase: @zero_address,
      state_root: @sepolia_state_root,
      transactions_root: @empty_trie_root,
      receipts_root: @empty_trie_root,
      logs_bloom: <<0::2048>>,
      difficulty: 131_072,
      number: 0,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_633_267_481,
      extra_data: @sepolia_extra_data,
      mix_hash: @zero_hash,
      nonce: <<0::64>>
    }
  end

  @doc "Returns the Holesky genesis block header."
  @spec holesky_header() :: BlockHeader.t()
  def holesky_header do
    %BlockHeader{
      parent_hash: @zero_hash,
      ommers_hash: @empty_ommers_hash,
      coinbase: @zero_address,
      state_root: @holesky_state_root,
      transactions_root: @empty_trie_root,
      receipts_root: @empty_trie_root,
      logs_bloom: <<0::2048>>,
      difficulty: 1,
      number: 0,
      gas_limit: 25_000_000,
      gas_used: 0,
      timestamp: 1_695_902_400,
      extra_data: @holesky_extra_data,
      mix_hash: @zero_hash,
      nonce: <<0::64>>
    }
  end

  @doc "Returns the genesis block header for the given network."
  @spec header(atom()) :: BlockHeader.t()
  def header(:mainnet), do: mainnet_header()
  def header(:sepolia), do: sepolia_header()
  def header(:holesky), do: holesky_header()

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

  @doc "Returns the Sepolia genesis block."
  @spec sepolia_block() :: Block.t()
  def sepolia_block do
    %Block{
      header: sepolia_header(),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  @doc "Returns the Holesky genesis block."
  @spec holesky_block() :: Block.t()
  def holesky_block do
    %Block{
      header: holesky_header(),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  @doc "Returns the genesis block for the given network."
  @spec block(atom()) :: Block.t()
  def block(:mainnet), do: mainnet_block()
  def block(:sepolia), do: sepolia_block()
  def block(:holesky), do: holesky_block()

  @doc "Returns the hash of the mainnet genesis block."
  @spec mainnet_genesis_hash() :: <<_::256>>
  def mainnet_genesis_hash do
    Encoding.block_hash(mainnet_header())
  end

  @doc "Returns the hash of the Sepolia genesis block."
  @spec sepolia_genesis_hash() :: <<_::256>>
  def sepolia_genesis_hash do
    Encoding.block_hash(sepolia_header())
  end

  @doc "Returns the hash of the Holesky genesis block."
  @spec holesky_genesis_hash() :: <<_::256>>
  def holesky_genesis_hash do
    Encoding.block_hash(holesky_header())
  end

  @doc "Returns the genesis hash for the given network."
  @spec genesis_hash(atom()) :: <<_::256>>
  def genesis_hash(:mainnet), do: mainnet_genesis_hash()
  def genesis_hash(:sepolia), do: sepolia_genesis_hash()
  def genesis_hash(:holesky), do: holesky_genesis_hash()

  @doc """
  Initializes the store with the genesis block.

  Stores the genesis header, body, canonical hash, and sets the latest
  block number to 0.
  """
  @spec initialize(GenServer.server()) :: :ok | {:error, term()}
  def initialize(store \\ Store) do
    initialize(store, :mainnet)
  end

  @doc """
  Initializes the store with the genesis block for the given network.
  """
  @spec initialize(GenServer.server(), atom()) :: :ok | {:error, term()}
  def initialize(store, network) do
    genesis = block(network)
    block_hash = Encoding.block_hash(genesis.header)
    encoded_header = Encoding.encode_header(genesis.header)
    encoded_body = Encoding.encode_body(genesis.transactions, genesis.ommers, genesis.withdrawals)

    with :ok <- Store.put_block_header(store, block_hash, encoded_header),
         :ok <- Store.put_block_body(store, block_hash, encoded_body),
         :ok <- Store.set_canonical_hash(store, 0, block_hash),
         :ok <- Store.set_latest_block_number(store, 0) do
      :ok
    end
  end
end
