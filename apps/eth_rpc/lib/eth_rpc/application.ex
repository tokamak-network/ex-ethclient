defmodule EthRpc.Application do
  @moduledoc """
  OTP Application for the JSON-RPC server.

  Starts a Bandit HTTP server, PayloadManager, and ForkChoice
  GenServers when `start_server` config is true.
  """

  use Application

  @impl true
  @spec start(Application.start_type(), term()) ::
          {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_rpc, :start_server, true) do
        port = Application.get_env(:eth_rpc, :port, 8545)

        [
          EthRpc.PayloadManager,
          EthRpc.ForkChoice,
          {Bandit, plug: EthRpc.Router, port: port, scheme: :http}
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: EthRpc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
