import Config

if config_env() == :prod do
  config :logger, level: :info

  config :eth_net,
    port: String.to_integer(System.get_env("ETH_PORT", "30303")),
    datadir: System.get_env("ETH_DATADIR", "./data"),
    chain: :mainnet

  config :eth_storage,
    backend: EthStorage.Backend.RocksDB,
    backend_opts: [datadir: System.get_env("DATADIR", "./data/storage")]
end
