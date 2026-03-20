defmodule EthStorage.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_storage, :start_services, true) do
        [{EthStorage.Store, [name: EthStorage.Store]}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: EthStorage.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
