import Config

config :logger, level: :warning

# Don't start the full supervision tree in tests
config :eth_net, start_services: false

config :eth_storage,
  backend: EthStorage.Backend.Memory,
  backend_opts: [],
  start_services: false

config :eth_chain,
  start_services: false,
  evm_module: EthVm.Mock

# Don't start the Bandit HTTP server in tests
config :eth_rpc, start_server: false
