defmodule EthDashboard.Application do
  @moduledoc """
  OTP Application for the dashboard.

  Starts the Collector GenServer and Bandit HTTP server.
  Controlled by the `:eth_dashboard, :start_server` config flag.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_dashboard, :start_server, true) do
        port = Application.get_env(:eth_dashboard, :port, 4000)

        [
          EthDashboard.Collector,
          {Bandit, plug: EthDashboard.Router, port: port, scheme: :http}
        ]
      else
        # In test mode, only start the collector
        [EthDashboard.Collector]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: EthDashboard.Supervisor)
  end
end
