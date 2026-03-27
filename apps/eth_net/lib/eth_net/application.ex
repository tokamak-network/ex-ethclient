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
          {EthNet.Peer.Scorer, []},
          {EthNet.Peer.ConnectionSupervisor, []},
          {EthNet.Peer.Manager, []}
        ]
      else
        []
      end

    opts = [strategy: :rest_for_one, name: EthNet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Called before the application stops.

  Disconnects all peers gracefully by terminating connections in the
  DynamicSupervisor, allowing each connection to send a P2P disconnect message.
  """
  @impl true
  @spec prep_stop(term()) :: term()
  def prep_stop(state) do
    if Application.get_env(:eth_net, :start_services, true) do
      case Process.whereis(EthNet.Peer.ConnectionSupervisor) do
        nil ->
          :ok

        _pid ->
          try do
            children = DynamicSupervisor.which_children(EthNet.Peer.ConnectionSupervisor)

            Enum.each(children, fn {:undefined, child_pid, _type, _modules} ->
              if is_pid(child_pid) do
                DynamicSupervisor.terminate_child(
                  EthNet.Peer.ConnectionSupervisor,
                  child_pid
                )
              end
            end)
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
      end
    end

    state
  end
end
