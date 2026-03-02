import Config

config :logger, :console,
  level: :info,
  format: "$date $time [$level] $metadata$message\n"

import_config "#{config_env()}.exs"
