defmodule EthRpc.MetricsPoller do
  @moduledoc """
  Periodically measures system gauges and updates the metrics store.

  Polls the following values on a configurable interval (default 5 seconds):
  - `eth.chain.height` — current block height from the store
  - `eth.peer.count` — number of connected peers
  - `eth.mempool.size` — number of pending transactions in the mempool
  - `eth.sync.progress` — sync progress percentage (placeholder)
  """

  @default_period 5_000

  @doc "Returns the child spec for the telemetry poller."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    period = Keyword.get(opts, :period, @default_period)

    %{
      id: __MODULE__,
      start:
        {:telemetry_poller, :start_link,
         [
           [
             measurements: [
               {__MODULE__, :measure_chain_height, []},
               {__MODULE__, :measure_peer_count, []},
               {__MODULE__, :measure_mempool_size, []},
               {__MODULE__, :measure_sync_progress, []}
             ],
             period: period,
             name: __MODULE__
           ]
         ]}
    }
  end

  @doc "Measures the current chain height and sets the gauge."
  @spec measure_chain_height() :: :ok
  def measure_chain_height do
    height =
      try do
        case EthStorage.Store.get_latest_block_number() do
          {:ok, n} when is_integer(n) -> n
          _ -> 0
        end
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    EthRpc.Metrics.set_gauge(:chain_height, height)
    :ok
  end

  @doc "Measures the current connected peer count and sets the gauge."
  @spec measure_peer_count() :: :ok
  def measure_peer_count do
    count =
      try do
        EthNet.Peer.Manager.connected_count()
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    EthRpc.Metrics.set_gauge(:peer_count, count)
    :ok
  end

  @doc "Measures the current mempool size and sets the gauge."
  @spec measure_mempool_size() :: :ok
  def measure_mempool_size do
    size =
      try do
        EthChain.Mempool.size()
      rescue
        _ -> 0
      catch
        :exit, _ -> 0
      end

    EthRpc.Metrics.set_gauge(:mempool_size, size)
    :ok
  end

  @doc "Measures sync progress as a percentage gauge (placeholder)."
  @spec measure_sync_progress() :: :ok
  def measure_sync_progress do
    # Placeholder: always 100.0 until sync module is implemented
    EthRpc.Metrics.set_gauge(:sync_progress, 100.0)
    :ok
  end
end
