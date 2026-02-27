import Config

config :logger, level: :warning

# Don't start the full supervision tree in tests
config :eth_net, start_services: false
