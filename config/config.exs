import Config

config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:module]

config :eth_storage,
  backend: EthStorage.Backend.Memory,
  backend_opts: []

import_config "#{config_env()}.exs"
