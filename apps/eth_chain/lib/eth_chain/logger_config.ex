defmodule EthChain.LoggerConfig do
  @moduledoc "Configures structured logging for the node."

  require Logger

  @doc "Sets up logger with node context metadata."
  @spec setup(EthChain.Config.t()) :: :ok
  def setup(%EthChain.Config{} = config) do
    Logger.metadata(
      chain_id: config.chain_id,
      node: "ex_ethclient/0.1.0"
    )

    :ok
  end
end
