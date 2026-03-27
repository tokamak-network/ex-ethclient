import Config

config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:module]

config :eth_storage,
  backend: EthStorage.Backend.Memory,
  backend_opts: [],
  pruning: false,
  retain_blocks: 128

config :eth_dashboard,
  port: 4000,
  start_server: false

import_config "#{config_env()}.exs"
