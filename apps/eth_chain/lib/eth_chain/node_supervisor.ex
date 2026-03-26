defmodule EthChain.NodeSupervisor do
  @moduledoc """
  Supervises all components of the Ethereum execution client.

  Start order:
  1. Storage (EthStorage.Store)
  2. Mempool (EthChain.Mempool)
  3. Genesis initialization (one-time task)
  4. Sync Manager (EthNet.Sync.Manager)
  """

  use Supervisor

  require Logger

  @doc "Starts the node supervisor with the given config."
  @spec start_link(EthChain.Config.t()) :: Supervisor.on_start()
  def start_link(%EthChain.Config{} = config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(%EthChain.Config{} = config) do
    EthChain.LoggerConfig.setup(config)

    children =
      [
        maybe_start_store(config),
        maybe_start_mempool(),
        genesis_task(),
        maybe_start_sync_manager(),
        maybe_start_beacon_fetcher()
      ]
      |> List.flatten()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp maybe_start_store(_config) do
    if Process.whereis(EthStorage.Store) do
      []
    else
      [{EthStorage.Store, [name: EthStorage.Store]}]
    end
  end

  defp maybe_start_mempool do
    if Process.whereis(EthChain.Mempool) do
      []
    else
      [{EthChain.Mempool, [name: EthChain.Mempool]}]
    end
  end

  defp maybe_start_sync_manager do
    if Process.whereis(EthNet.Sync.Manager) do
      []
    else
      [{EthNet.Sync.Manager, []}]
    end
  end

  defp maybe_start_beacon_fetcher do
    case Application.get_env(:eth_chain, :beacon_api_endpoint) do
      nil ->
        []

      endpoint when is_binary(endpoint) ->
        network = Application.get_env(:eth_chain, :network, :mainnet)

        if Process.whereis(EthChain.BeaconFetcher) do
          []
        else
          [{EthChain.BeaconFetcher, [endpoint: endpoint, network: network]}]
        end
    end
  end

  @spec genesis_task() :: Supervisor.child_spec()
  defp genesis_task do
    %{
      id: :genesis_init,
      start: {Task, :start_link, [fn -> EthChain.Node.initialize(EthStorage.Store) end]},
      restart: :temporary
    }
  end

  # TODO: Wire up RPC child when NodeSupervisor manages the full stack
  # @spec maybe_add_rpc([Supervisor.child_spec()], EthChain.Config.t()) ::
  #         [Supervisor.child_spec()]
  # defp maybe_add_rpc(children, %EthChain.Config{rpc_enabled: false}), do: children
  #
  # defp maybe_add_rpc(children, %EthChain.Config{rpc_enabled: true, rpc_port: port}) do
  #   if Code.ensure_loaded?(Bandit) do
  #     children ++ [rpc_child_spec(port)]
  #   else
  #     children
  #   end
  # end
  #
  # @spec rpc_child_spec(non_neg_integer()) :: Supervisor.child_spec()
  # defp rpc_child_spec(port) do
  #   {Bandit, plug: EthRpc.Router, port: port}
  # end
end
