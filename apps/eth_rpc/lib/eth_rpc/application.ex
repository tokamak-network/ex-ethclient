defmodule EthRpc.Application do
  @moduledoc """
  OTP Application for the JSON-RPC server.

  Starts two Bandit HTTP servers when `start_server` config is true:
  - Port 8545 (configurable): regular RPC (eth_, net_, web3_)
  - Port 8551 (configurable): Engine API (engine_*) with JWT auth

  Also starts PayloadManager, ForkChoice, and FilterManager GenServers.
  """

  use Application

  @impl true
  @spec start(Application.start_type(), term()) ::
          {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    metrics_children =
      if Application.get_env(:eth_rpc, :start_metrics, true) do
        [
          EthRpc.Metrics,
          EthRpc.MetricsPoller.child_spec(period: 5_000)
        ]
      else
        []
      end

    children =
      if Application.get_env(:eth_rpc, :start_server, true) do
        rpc_port = Application.get_env(:eth_rpc, :port, 8545)
        engine_port = Application.get_env(:eth_rpc, :engine_port, 8551)

        metrics_children ++
          [
            EthRpc.PayloadManager,
            EthRpc.ForkChoice,
            EthRpc.FilterManager,
            Supervisor.child_spec(
              {Bandit, plug: EthRpc.Router, port: rpc_port, scheme: :http},
              id: :rpc_server
            ),
            Supervisor.child_spec(
              {Bandit, plug: EthRpc.EngineRouter, port: engine_port, scheme: :http},
              id: :engine_server
            )
          ]
      else
        metrics_children
      end

    opts = [strategy: :one_for_one, name: EthRpc.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
