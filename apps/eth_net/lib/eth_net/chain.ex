defmodule EthNet.Chain do
  @moduledoc """
  Ethereum chain constants for mainnet, Sepolia, and Holesky testnets.
  Genesis hash, network ID, fork schedule, terminal total difficulty, and bootnodes.
  """

  @mainnet_genesis_hash Base.decode16!(
                          "D4E56740F876AEF8C010B86A40D5F56745A118D0906A34E69AEC8C0DB1CB8FA3",
                          case: :upper
                        )
  @mainnet_network_id 1

  # Terminal total difficulty for The Merge (PoS transition)
  @mainnet_terminal_td 58_750_000_000_000_000_000_000

  # Fork schedule: block-based forks first, then timestamp-based forks
  @mainnet_block_forks [
    {:homestead, 1_150_000},
    {:dao_fork, 1_920_000},
    {:tangerine_whistle, 2_463_000},
    {:spurious_dragon, 2_675_000},
    {:byzantium, 4_370_000},
    {:constantinople, 7_280_000},
    {:petersburg, 7_280_000},
    {:istanbul, 9_069_000},
    {:muir_glacier, 9_200_000},
    {:berlin, 12_244_000},
    {:london, 12_965_000},
    {:arrow_glacier, 13_773_000},
    {:gray_glacier, 15_050_000}
  ]

  # Post-merge forks use timestamps
  @mainnet_time_forks [
    {:paris, 15_537_394},
    {:shanghai, 1_681_338_455},
    {:cancun, 1_710_338_135}
  ]

  # Ethereum Foundation mainnet bootnodes (geth defaults)
  @mainnet_bootnodes [
    "enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303",
    "enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303",
    "enode://2b252ab6a1d0f971d9722cb839a42cb81db019ba44c08754628ab4a823487071b5695317c8ccd085219c3a03af063495b2f1da8d18218da2d6a82981b45e6ffc@65.108.70.101:30303",
    "enode://4aeb4ab6c14b23e2c4cfdce879c04b0748a20d8e9b59e25ded2a08143e265c6c25936e74cbc8e641e3312ca288673d91f2f93f8e277de3cfa444ecdaaf982052@157.90.35.166:30303",
    # Additional mainnet bootnodes (Ethereum Foundation)
    "enode://c1f8b7c2ac4453271fa07d8e9ecf9a2e8285aa0cefb6fc271c2c52ad5beebbcb8d48d31b40a3b4f7dff5e35707e3bdca000af432e8089915f42f26e1ff3a09e1@167.99.31.227:30303"
  ]

  # --- Sepolia testnet ---

  @sepolia_genesis_hash Base.decode16!(
                          "25A5CC106EEA7138ACAB33231D7160D69CB777EE0C2C553FCDDF5138993E6DD9",
                          case: :upper
                        )
  @sepolia_network_id 11_155_111

  # Terminal total difficulty for The Merge on Sepolia
  @sepolia_terminal_td 17_000_000_000_000_000

  # Sepolia had no pre-merge block-based forks (launched post-Merge-ready)
  @sepolia_block_forks []

  # Post-merge forks use timestamps
  @sepolia_time_forks [
    {:shanghai, 1_677_557_088},
    {:cancun, 1_706_655_072}
  ]

  @sepolia_bootnodes [
    "enode://9246d00bc8fd1742e5ad2428b80fc4dc45d786283e05ef6edbd9002cbc335d40998444732fbe921cb88e1d2c73d1b1de53bae6a2237996e9bfe14f871baf7571@18.168.182.86:30303",
    "enode://ec66ddcf1a974950bd4c782789a7e04f8aa7110a72569b6e65fcd51e937e74eed303b1ea734e4d19cfaec9fbff9b6ee65bf31dcb50ba79acce9dd63a6aca61c7@52.14.151.177:30303"
  ]

  # --- Holesky testnet ---

  @holesky_genesis_hash Base.decode16!(
                          "B5F7F912443C940F21FD98071C45F5F2AF38E5F40E2C6574C6D233F0505B88F2",
                          case: :upper
                        )
  @holesky_network_id 17_000

  # Holesky is PoS from genesis (no PoW transition)
  @holesky_terminal_td 0

  # Holesky had no pre-merge block-based forks (launched post-Merge)
  @holesky_block_forks []

  # Post-merge forks use timestamps
  @holesky_time_forks [
    {:shanghai, 1_696_000_704},
    {:cancun, 1_707_305_664},
    {:prague, 1_740_434_112}
  ]

  # Official Holesky bootnodes (Ethereum Foundation)
  @holesky_bootnodes [
    "enode://ac906289e4b7f12df423d654c5a962b6ebe5b3a74cc9e06571c0bf024bc56e1b0a72e3d23b6c4e6ff0c47b9d78a4e6be2add6b1fcb0e49e3f2e15aae20b76a96@18.138.108.67:30303",
    "enode://a3435a0155a3e837c02f5e7f53571c965eed2a2702652038d2845e820e465df93a29af3827e27d5b57c8f0f0eda48f693e986ab44f10d582e9d3f0d65e93dcaf@95.217.233.99:30303",
    "enode://5d0ce3237ff02ece3d838e081a42bab21e174689e6cffbd6bfeadbb0e6bdf48bcf4f1f76dab0c7f08f2e2e5fd4e0e79c8e49dd6a225eaff0b6b7bc3523b319b4@65.109.20.113:30303"
  ]

  # --- Public API ---

  @doc "Returns the genesis hash for the given network."
  @spec genesis_hash(atom()) :: <<_::256>>
  def genesis_hash(:mainnet), do: @mainnet_genesis_hash
  def genesis_hash(:sepolia), do: @sepolia_genesis_hash
  def genesis_hash(:holesky), do: @holesky_genesis_hash

  @doc "Returns the network ID for the given network."
  @spec network_id(atom()) :: non_neg_integer()
  def network_id(:mainnet), do: @mainnet_network_id
  def network_id(:sepolia), do: @sepolia_network_id
  def network_id(:holesky), do: @holesky_network_id

  @doc "Returns the terminal total difficulty for the given network."
  @spec terminal_td(atom()) :: non_neg_integer()
  def terminal_td(:mainnet), do: @mainnet_terminal_td
  def terminal_td(:sepolia), do: @sepolia_terminal_td
  def terminal_td(:holesky), do: @holesky_terminal_td

  @doc "Returns the block-based fork schedule for the given network."
  @spec block_forks(atom()) :: [{atom(), non_neg_integer()}]
  def block_forks(:mainnet), do: @mainnet_block_forks
  def block_forks(:sepolia), do: @sepolia_block_forks
  def block_forks(:holesky), do: @holesky_block_forks

  @doc "Returns the timestamp-based fork schedule for the given network."
  @spec time_forks(atom()) :: [{atom(), non_neg_integer()}]
  def time_forks(:mainnet), do: @mainnet_time_forks
  def time_forks(:sepolia), do: @sepolia_time_forks
  def time_forks(:holesky), do: @holesky_time_forks

  @doc "Returns the bootnode enode URLs for the given network."
  @spec bootnodes(atom()) :: [String.t()]
  def bootnodes(:mainnet), do: @mainnet_bootnodes
  def bootnodes(:sepolia), do: @sepolia_bootnodes
  def bootnodes(:holesky), do: @holesky_bootnodes

  @doc "Returns all fork values in order: block-based then timestamp-based."
  @spec all_fork_values(atom()) :: {[non_neg_integer()], [non_neg_integer()]}
  def all_fork_values(network) do
    block_values =
      block_forks(network)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    time_values =
      time_forks(network)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    {block_values, time_values}
  end
end
