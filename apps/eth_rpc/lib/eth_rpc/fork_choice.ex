defmodule EthRpc.ForkChoice do
  @moduledoc "Tracks consensus layer fork choice state."

  use GenServer

  @zero_hash <<0::256>>

  # --- Public API ---

  @doc "Starts the fork choice tracker."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Updates fork choice with new head, safe, and finalized hashes."
  @spec update(<<_::256>>, <<_::256>>, <<_::256>>, GenServer.server()) ::
          :ok
  def update(head_hash, safe_hash, finalized_hash, server \\ __MODULE__) do
    GenServer.call(
      server,
      {:update, head_hash, safe_hash, finalized_hash}
    )
  end

  @doc "Gets current fork choice state."
  @spec get_state(GenServer.server()) :: map()
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok,
     %{
       head_hash: @zero_hash,
       safe_hash: @zero_hash,
       finalized_hash: @zero_hash
     }}
  end

  @impl true
  def handle_call({:update, head, safe, finalized}, _from, _state) do
    new_state = %{
      head_hash: head,
      safe_hash: safe,
      finalized_hash: finalized
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
