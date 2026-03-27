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
        [
          {EthChain.Mempool, []},
          {EthChain.ShutdownManager, []}
        ]
      else
        []
      end

    opts = [strategy: :one_for_one, name: EthChain.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Called before the application stops.

  Initiates the graceful shutdown sequence via ShutdownManager if running.
  """
  @impl true
  @spec prep_stop(term()) :: term()
  def prep_stop(state) do
    if Application.get_env(:eth_chain, :start_services, true) do
      case Process.whereis(EthChain.ShutdownManager) do
        nil -> :ok
        _pid -> EthChain.ShutdownManager.initiate_shutdown()
      end
    end

    state
  end
end
