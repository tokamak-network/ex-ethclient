import Config

config :logger, level: :warning

# Don't start the full supervision tree in tests
config :eth_net, start_services: false
config :eth_storage, start_services: false
config :eth_chain, start_services: false

# Don't start the Bandit HTTP server in tests
config :eth_rpc, start_server: false
