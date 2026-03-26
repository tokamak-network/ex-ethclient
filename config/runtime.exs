import Config

if config_env() == :prod do
  # Log level — supports Hive LOG_LEVEL env var
  log_level =
    case System.get_env("LOG_LEVEL", "info") do
      "debug" -> :debug
      "warning" -> :warning
      "error" -> :error
      "none" -> :none
      _ -> :info
    end

  config :logger, level: log_level

  # P2P networking
  config :eth_net,
    port: String.to_integer(System.get_env("ETH_PORT", "30303")),
    datadir: System.get_env("ETH_DATADIR", "./data"),
    chain: :mainnet

  # Bootnodes — comma-separated enode URIs (set by Hive via entrypoint)
  if bootnodes = System.get_env("ETH_BOOTNODES") do
    config :eth_chain,
      bootnodes: String.split(bootnodes, ",", trim: true)
  end

  # Chain / network identity (Hive-injected)
  if chain_id = System.get_env("ETH_CHAIN_ID") do
    config :eth_chain, chain_id: String.to_integer(chain_id)
  end

  if network_id = System.get_env("ETH_NETWORK_ID") do
    config :eth_chain, network_id: String.to_integer(network_id)
  end

  # RPC ports
  config :eth_rpc,
    port: String.to_integer(System.get_env("ETH_RPC_PORT", "8545")),
    engine_port: String.to_integer(System.get_env("ETH_ENGINE_PORT", "8551"))

  # JWT secret for Engine API (Hive mounts this file)
  if jwt_path = System.get_env("ETH_JWT_SECRET") do
    config :eth_rpc, jwt_secret_path: jwt_path
  end

  # Genesis file path (Hive mounts /genesis.json)
  if genesis = System.get_env("ETH_GENESIS") do
    config :eth_chain, genesis_path: genesis
  end

  # Storage
  config :eth_storage,
    backend: EthStorage.Backend.RocksDB,
    backend_opts: [datadir: System.get_env("DATADIR", "./data/storage")]
end
