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
        [{EthStorage.Store, [name: EthStorage.Store]}]
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

  @spec initialize_genesis() :: :ok | {:error, term()}
  defp initialize_genesis do
    case EthStorage.BlockStore.latest_block_number(EthStorage.Store) do
      {:ok, nil} -> EthStorage.Genesis.initialize(EthStorage.Store)
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end
