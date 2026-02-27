defmodule EthNet.Chain do
  @moduledoc """
  Ethereum chain constants for mainnet.
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

  @mainnet_bootnodes [
    "enode://d860a01f9722d78051619d1e2351aba3f43f943f6f00718d1b9baa4101932a1f5011f16bb2b1bb35db20d6fe28fa0bf09636d26a87d31de9ec6203eeedb1f666@18.138.108.67:30303",
    "enode://22a8232c3abc76a16ae9d6c3b164f98775fe226f0917b0ca871128a74a8e9630b458460865bab457221f1d448dd9791d24c4e5d88786180ac185df813a68d4de@3.209.45.79:30303",
    "enode://2b252ab6a1d0f971d9722cb839a42cb81db019ba44c08754628ab4a823487071b5695317c8ccd085219c3a03af063495b2f1da8d18218da2d6a82981b45e6ffc@65.108.70.101:30303",
    "enode://4aeb4ab6c14b23e2c4cfdce879c04b0748a20d8e9b59e25ded2a08143e265c6c25936e74cbc8e641e3312ca288673d91f2f93f8e277de3cfa444ecdaaf982052@157.90.35.166:30303"
  ]

  def genesis_hash(:mainnet), do: @mainnet_genesis_hash
  def network_id(:mainnet), do: @mainnet_network_id
  def terminal_td(:mainnet), do: @mainnet_terminal_td
  def block_forks(:mainnet), do: @mainnet_block_forks
  def time_forks(:mainnet), do: @mainnet_time_forks
  def bootnodes(:mainnet), do: @mainnet_bootnodes

  @doc "Returns all fork values in order: block-based then timestamp-based."
  def all_fork_values(:mainnet) do
    block_values =
      @mainnet_block_forks
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    time_values =
      @mainnet_time_forks
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    {block_values, time_values}
  end
end
