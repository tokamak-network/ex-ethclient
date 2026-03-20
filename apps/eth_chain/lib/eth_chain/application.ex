defmodule EthChain.Application do
  @moduledoc """
  OTP Application for the eth_chain app.

  Starts the Mempool GenServer unless `config :eth_chain, start_services: false`.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_chain, :start_services, true) do
        [{EthChain.Mempool, []}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: EthChain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
