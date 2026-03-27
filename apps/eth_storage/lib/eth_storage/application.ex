defmodule EthStorage.Application do
  @moduledoc """
  OTP Application for the eth_storage app.

  Starts the Store GenServer unless `config :eth_storage, start_services: false`.
  When the Store starts, initializes the genesis block if not yet initialized.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:eth_storage, :start_services, true) do
        backend = Application.get_env(:eth_storage, :backend, EthStorage.Backend.Memory)
        backend_opts = Application.get_env(:eth_storage, :backend_opts, [])

        store_child =
          {EthStorage.Store,
           [name: EthStorage.Store, backend: backend, backend_opts: backend_opts]}

        pruning_enabled = Application.get_env(:eth_storage, :pruning, false)
        retain_blocks = Application.get_env(:eth_storage, :retain_blocks, 128)

        if pruning_enabled do
          [
            store_child,
            {EthStorage.Pruner,
             [name: EthStorage.Pruner, retain_blocks: retain_blocks, store: EthStorage.Store]}
          ]
        else
          [store_child]
        end
      else
        []
      end

    opts = [strategy: :one_for_one, name: EthStorage.Supervisor]
    result = Supervisor.start_link(children, opts)

    if Application.get_env(:eth_storage, :start_services, true) do
      initialize_genesis()
    end

    result
  end

  @doc """
  Called before the application stops.

  Flushes any buffered storage writes to ensure data integrity on shutdown.
  """
  @impl true
  @spec prep_stop(term()) :: term()
  def prep_stop(state) do
    if Application.get_env(:eth_storage, :start_services, true) do
      case Process.whereis(EthStorage.Store) do
        nil ->
          :ok

        _pid ->
          try do
            EthStorage.Store.flush()
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end
      end
    end

    state
  end

  @spec initialize_genesis() :: :ok | {:error, term()}
  defp initialize_genesis do
    case EthStorage.BlockStore.latest_block_number(EthStorage.Store) do
      {:ok, nil} -> EthStorage.Genesis.initialize(EthStorage.Store)
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
