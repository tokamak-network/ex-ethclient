defmodule EthChain.NodeSupervisor do
  @moduledoc """
  Supervises all components of the Ethereum execution client.

  Start order:
  1. Storage (EthStorage.Store)
  2. Mempool (EthChain.Mempool)
  3. Genesis initialization (one-time task)
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
        {EthStorage.Store, [name: EthStorage.Store, backend: backend_for(config)]},
        {EthChain.Mempool, [name: EthChain.Mempool]},
        genesis_task()
      ]
      |> maybe_add_rpc(config)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec backend_for(EthChain.Config.t()) :: module()
  defp backend_for(%EthChain.Config{}), do: EthStorage.Backend.Memory

  @spec genesis_task() :: Supervisor.child_spec()
  defp genesis_task do
    %{
      id: :genesis_init,
      start: {Task, :start_link, [fn -> EthChain.Node.initialize(EthStorage.Store) end]},
      restart: :temporary
    }
  end

  @spec maybe_add_rpc([Supervisor.child_spec()], EthChain.Config.t()) ::
          [Supervisor.child_spec()]
  defp maybe_add_rpc(children, %EthChain.Config{rpc_enabled: false}), do: children

  defp maybe_add_rpc(children, %EthChain.Config{rpc_enabled: true, rpc_port: port}) do
    if Code.ensure_loaded?(Bandit) do
      children ++ [rpc_child_spec(port)]
    else
      children
    end
  end

  @spec rpc_child_spec(non_neg_integer()) :: Supervisor.child_spec()
  defp rpc_child_spec(port) do
    {Bandit, plug: EthRpc.Router, port: port}
  end
end
