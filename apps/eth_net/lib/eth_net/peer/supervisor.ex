defmodule EthNet.Peer.ConnectionSupervisor do
  @moduledoc """
  DynamicSupervisor for peer TCP connections.
  Each child is an `EthNet.Peer.Connection` GenServer.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Starts a new peer connection."
  def start_connection(opts) do
    DynamicSupervisor.start_child(__MODULE__, {EthNet.Peer.Connection, opts})
  end

  @doc "Returns the count of active connections."
  def count do
    %{active: active} = DynamicSupervisor.count_children(__MODULE__)
    active
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 50)
  end
end
