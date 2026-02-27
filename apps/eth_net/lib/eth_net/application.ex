defmodule EthNet.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_net, :start_services, true) do
        port = Application.get_env(:eth_net, :port, 30303)
        datadir = Application.get_env(:eth_net, :datadir, "./data")
        chain = Application.get_env(:eth_net, :chain, :mainnet)

        [
          {EthNet.NodeKey, datadir: datadir},
          {EthNet.DiscV4.Server, port: port, chain: chain},
          {EthNet.Peer.ConnectionSupervisor, []},
          {EthNet.Peer.Manager, []}
        ]
      else
        []
      end

    opts = [strategy: :rest_for_one, name: EthNet.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
