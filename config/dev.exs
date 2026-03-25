import Config

config :logger, level: :debug

config :eth_storage,
  backend: EthStorage.Backend.DETS,
  backend_opts: [datadir: "./data/storage"],
  start_services: true

config :eth_rpc, start_server: true
