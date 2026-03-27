defmodule EthRpc.Metrics do
  @moduledoc """
  Telemetry metrics definitions and Prometheus text formatter.

  Defines counters, gauges (via poller), and histograms for observability
  of the Ethereum execution client. Stores metric values in an ETS table
  and exposes them in Prometheus text format via `format_prometheus/0`.
  """

  use GenServer

  require Logger

  @table :eth_metrics
  @histogram_buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

  # -- Client API --

  @doc "Starts the metrics GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns all metrics formatted in Prometheus text exposition format."
  @spec format_prometheus() :: String.t()
  def format_prometheus do
    try do
      counters = format_counters()
      gauges = format_gauges()
      histograms = format_histograms()

      [counters, gauges, histograms]
      |> List.flatten()
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    rescue
      ArgumentError -> "# No metrics available\n"
    end
  end

  @doc "Increments a counter metric."
  @spec increment_counter(atom(), map()) :: :ok
  def increment_counter(name, labels \\ %{}) do
    key = {:counter, name, labels}

    try do
      :ets.update_counter(@table, key, {2, 1}, {key, 0})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc "Sets a gauge metric to a specific value."
  @spec set_gauge(atom(), number()) :: :ok
  def set_gauge(name, value) do
    key = {:gauge, name}

    try do
      :ets.insert(@table, {key, value})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc "Records a histogram observation."
  @spec observe_histogram(atom(), number(), map()) :: :ok
  def observe_histogram(name, value, labels \\ %{}) do
    sum_key = {:histogram_sum, name, labels}
    count_key = {:histogram_count, name, labels}

    try do
      :ets.update_counter(@table, count_key, {2, 1}, {count_key, 0})

      case :ets.lookup(@table, sum_key) do
        [{^sum_key, current}] ->
          :ets.insert(@table, {sum_key, current + value})

        [] ->
          :ets.insert(@table, {sum_key, value})
      end

      Enum.each(@histogram_buckets, fn bucket ->
        if value <= bucket do
          bucket_key = {:histogram_bucket, name, labels, bucket}
          :ets.update_counter(@table, bucket_key, {2, 1}, {bucket_key, 0})
        end
      end)

      inf_key = {:histogram_bucket, name, labels, :infinity}
      :ets.update_counter(@table, inf_key, {2, 1}, {inf_key, 0})
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc "Returns the current value of a counter."
  @spec get_counter(atom(), map()) :: non_neg_integer()
  def get_counter(name, labels \\ %{}) do
    key = {:counter, name, labels}

    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  rescue
    ArgumentError -> 0
  end

  @doc "Returns the current value of a gauge."
  @spec get_gauge(atom()) :: number()
  def get_gauge(name) do
    key = {:gauge, name}

    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  rescue
    ArgumentError -> 0
  end

  # -- Telemetry event definitions --

  @doc "Returns the list of telemetry events this module handles."
  @spec telemetry_events() :: [list()]
  def telemetry_events do
    [
      [:eth, :rpc, :request, :stop],
      [:eth, :block, :processed],
      [:eth, :tx, :processed],
      [:eth, :peer, :connected],
      [:eth, :peer, :disconnected]
    ]
  end

  @doc "Returns telemetry_metrics definitions for documentation."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      Telemetry.Metrics.counter("eth.rpc.request.count",
        event_name: [:eth, :rpc, :request, :stop],
        tags: [:method]
      ),
      Telemetry.Metrics.distribution("eth.rpc.request.duration",
        event_name: [:eth, :rpc, :request, :stop],
        measurement: :duration,
        tags: [:method],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("eth.block.processed.count",
        event_name: [:eth, :block, :processed]
      ),
      Telemetry.Metrics.distribution("eth.block.processing.duration",
        event_name: [:eth, :block, :processed],
        measurement: :duration,
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("eth.tx.processed.count",
        event_name: [:eth, :tx, :processed]
      ),
      Telemetry.Metrics.counter("eth.peer.connected.count",
        event_name: [:eth, :peer, :connected]
      ),
      Telemetry.Metrics.counter("eth.peer.disconnected.count",
        event_name: [:eth, :peer, :disconnected]
      ),
      Telemetry.Metrics.last_value("eth.chain.height"),
      Telemetry.Metrics.last_value("eth.peer.count"),
      Telemetry.Metrics.last_value("eth.mempool.size")
    ]
  end

  # -- Server Callbacks --

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :set, {:write_concurrency, true}])
    attach_handlers()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # -- Private --

  @spec attach_handlers() :: :ok
  defp attach_handlers do
    :telemetry.attach(
      "eth-rpc-request",
      [:eth, :rpc, :request, :stop],
      &handle_rpc_request/4,
      nil
    )

    :telemetry.attach(
      "eth-block-processed",
      [:eth, :block, :processed],
      &handle_block_processed/4,
      nil
    )

    :telemetry.attach(
      "eth-tx-processed",
      [:eth, :tx, :processed],
      &handle_tx_processed/4,
      nil
    )

    :telemetry.attach(
      "eth-peer-connected",
      [:eth, :peer, :connected],
      &handle_peer_connected/4,
      nil
    )

    :telemetry.attach(
      "eth-peer-disconnected",
      [:eth, :peer, :disconnected],
      &handle_peer_disconnected/4,
      nil
    )

    :ok
  end

  @spec handle_rpc_request(list(), map(), map(), term()) :: :ok
  defp handle_rpc_request(_event, measurements, metadata, _config) do
    method = Map.get(metadata, :method, "unknown")
    duration_ms = Map.get(measurements, :duration, 0) / 1_000_000

    increment_counter(:rpc_request_total, %{method: method})
    observe_histogram(:rpc_request_duration_seconds, duration_ms / 1_000, %{method: method})
    :ok
  end

  @spec handle_block_processed(list(), map(), map(), term()) :: :ok
  defp handle_block_processed(_event, measurements, metadata, _config) do
    increment_counter(:block_processed_total, %{})
    tx_count = Map.get(metadata, :tx_count, 0)

    if tx_count > 0 do
      Enum.each(1..tx_count, fn _ ->
        increment_counter(:tx_processed_total, %{})
      end)
    end

    duration_ms = Map.get(measurements, :duration, 0) / 1_000_000
    observe_histogram(:block_processing_duration_seconds, duration_ms / 1_000, %{})
    :ok
  end

  @spec handle_tx_processed(list(), map(), map(), term()) :: :ok
  defp handle_tx_processed(_event, _measurements, _metadata, _config) do
    increment_counter(:tx_processed_total, %{})
    :ok
  end

  @spec handle_peer_connected(list(), map(), map(), term()) :: :ok
  defp handle_peer_connected(_event, _measurements, _metadata, _config) do
    increment_counter(:peer_connected_total, %{})
    :ok
  end

  @spec handle_peer_disconnected(list(), map(), map(), term()) :: :ok
  defp handle_peer_disconnected(_event, _measurements, _metadata, _config) do
    increment_counter(:peer_disconnected_total, %{})
    :ok
  end

  # -- Prometheus formatting --

  @spec format_counters() :: [String.t()]
  defp format_counters do
    entries =
      :ets.match_object(@table, {{:counter, :_, :_}, :_})

    entries
    |> Enum.group_by(fn {{:counter, name, _labels}, _val} -> name end)
    |> Enum.flat_map(fn {name, items} ->
      prom_name = "eth_#{name}"

      [
        "# HELP #{prom_name} Counter metric.",
        "# TYPE #{prom_name} counter"
        | Enum.map(items, fn {{:counter, _name, labels}, val} ->
            label_str = format_labels(labels)
            "#{prom_name}#{label_str} #{val}"
          end)
      ]
    end)
  end

  @spec format_gauges() :: [String.t()]
  defp format_gauges do
    entries =
      :ets.match_object(@table, {{:gauge, :_}, :_})

    Enum.flat_map(entries, fn {{:gauge, name}, val} ->
      prom_name = "eth_#{name}"

      [
        "# HELP #{prom_name} Gauge metric.",
        "# TYPE #{prom_name} gauge",
        "#{prom_name} #{val}"
      ]
    end)
  end

  @spec format_histograms() :: [String.t()]
  defp format_histograms do
    counts =
      :ets.match_object(@table, {{:histogram_count, :_, :_}, :_})

    counts
    |> Enum.group_by(fn {{:histogram_count, name, _labels}, _val} -> name end)
    |> Enum.flat_map(fn {name, items} ->
      prom_name = "eth_#{name}"

      [
        "# HELP #{prom_name} Histogram metric.",
        "# TYPE #{prom_name} histogram"
        | Enum.flat_map(items, fn {{:histogram_count, _name, labels}, count} ->
            sum_key = {:histogram_sum, name, labels}
            sum = lookup_value(sum_key, 0)

            label_str = format_labels(labels)
            base_labels = if labels == %{}, do: "", else: Map.to_list(labels)

            bucket_lines =
              Enum.map(@histogram_buckets, fn bucket ->
                bucket_key = {:histogram_bucket, name, labels, bucket}
                bucket_val = lookup_value(bucket_key, 0)
                le_labels = merge_label_str(base_labels, "le", "#{bucket}")
                "#{prom_name}_bucket{#{le_labels}} #{bucket_val}"
              end)

            inf_key = {:histogram_bucket, name, labels, :infinity}
            inf_val = lookup_value(inf_key, 0)
            inf_labels = merge_label_str(base_labels, "le", "+Inf")

            bucket_lines ++
              [
                "#{prom_name}_bucket{#{inf_labels}} #{inf_val}",
                "#{prom_name}_sum#{label_str} #{format_float(sum)}",
                "#{prom_name}_count#{label_str} #{count}"
              ]
          end)
      ]
    end)
  end

  @spec format_labels(map()) :: String.t()
  defp format_labels(labels) when map_size(labels) == 0, do: ""

  defp format_labels(labels) do
    inner =
      labels
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join(",")

    "{#{inner}}"
  end

  @spec merge_label_str(list() | String.t(), String.t(), String.t()) :: String.t()
  defp merge_label_str("", key, value), do: "#{key}=\"#{value}\""

  defp merge_label_str(pairs, key, value) when is_list(pairs) do
    existing =
      pairs
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join(",")

    "#{existing},#{key}=\"#{value}\""
  end

  @spec lookup_value(tuple(), number()) :: number()
  defp lookup_value(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      [] -> default
    end
  end

  @spec format_float(number()) :: String.t()
  defp format_float(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 6)
  defp format_float(val) when is_integer(val), do: "#{val}.000000"
end
