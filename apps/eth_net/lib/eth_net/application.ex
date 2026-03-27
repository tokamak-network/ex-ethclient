defmodule EthNet.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_net, :start_services, true) do
        port = Application.get_env(:eth_net, :port, 30303)
        discv5_port = Application.get_env(:eth_net, :discv5_port, 30304)
        datadir = Application.get_env(:eth_net, :datadir, "./data")
        chain = Application.get_env(:eth_net, :chain, :mainnet)
        start_discv5 = Application.get_env(:eth_net, :start_discv5, false)
        dns_discovery = Application.get_env(:eth_net, :dns_discovery, false)
        dns_seeds = Application.get_env(:eth_net, :dns_seeds, [])
        dns_sync_interval = Application.get_env(:eth_net, :dns_sync_interval, 1_800_000)

        base = [
          {EthNet.NodeKey, datadir: datadir},
          {EthNet.DiscV4.Server, port: port, chain: chain},
          {EthNet.Peer.Scorer, []},
          {EthNet.Peer.ConnectionSupervisor, []},
          {EthNet.Peer.Manager, []}
        ]

        base =
          if start_discv5 do
            base ++ [{EthNet.DiscV5.Server, port: discv5_port}]
          else
            base
          end

        if dns_discovery do
          dns_opts = [seeds: dns_seeds, sync_interval: dns_sync_interval]
          base ++ [{EthNet.DNS.Resolver, dns_opts}]
        else
          base
        end
      else
        []
      end

    opts = [strategy: :rest_for_one, name: EthNet.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
