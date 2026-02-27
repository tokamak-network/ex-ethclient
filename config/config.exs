import Config

config :logger, :console,
  format: "$time [$level] $metadata$message\n",
  metadata: [:module]

import_config "#{config_env()}.exs"
