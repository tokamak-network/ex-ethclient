defmodule EthNet.Peer.Scorer do
  @moduledoc """
  Peer scoring and rate limiting for P2P connections.

  Tracks per-peer metrics (response times, success/failure counts) and
  computes a reputation score. Peers below a threshold are flagged for
  disconnection. Also enforces per-peer message rate limits.
  """

  use GenServer

  require Logger

  @type peer_id :: binary()

  @type peer_stats :: %{
          score: float(),
          successes: non_neg_integer(),
          failures: non_neg_integer(),
          timeouts: non_neg_integer(),
          total_latency_ms: non_neg_integer(),
          last_seen: integer(),
          message_count: non_neg_integer(),
          window_start: integer()
        }

  @base_score 50.0
  @disconnect_threshold -50.0
  @decay_interval 60_000
  @decay_amount 2.0
  @max_messages_per_second 100
  @rate_window_ms 1_000

  defstruct peers: %{}

  # --- Public API ---

  @doc "Starts the Scorer GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Records a successful response from a peer with latency in ms."
  @spec record_success(GenServer.server(), peer_id(), non_neg_integer()) :: :ok
  def record_success(server \\ __MODULE__, peer_id, latency_ms) do
    GenServer.cast(server, {:success, peer_id, latency_ms})
  end

  @doc "Records a failed response from a peer."
  @spec record_failure(GenServer.server(), peer_id()) :: :ok
  def record_failure(server \\ __MODULE__, peer_id) do
    GenServer.cast(server, {:failure, peer_id})
  end

  @doc "Records a timeout from a peer."
  @spec record_timeout(GenServer.server(), peer_id()) :: :ok
  def record_timeout(server \\ __MODULE__, peer_id) do
    GenServer.cast(server, {:timeout, peer_id})
  end

  @doc "Returns the score for a given peer, or the base score if unknown."
  @spec get_score(GenServer.server(), peer_id()) :: float()
  def get_score(server \\ __MODULE__, peer_id) do
    GenServer.call(server, {:get_score, peer_id})
  end

  @doc "Returns up to `count` peers sorted by descending score."
  @spec get_best_peers(GenServer.server(), non_neg_integer()) :: [{peer_id(), float()}]
  def get_best_peers(server \\ __MODULE__, count) do
    GenServer.call(server, {:best_peers, count})
  end

  @doc "Returns peer IDs with scores below the disconnect threshold."
  @spec get_bad_peers(GenServer.server()) :: [peer_id()]
  def get_bad_peers(server \\ __MODULE__) do
    GenServer.call(server, :bad_peers)
  end

  @doc """
  Checks if a peer exceeds the message rate limit.

  Returns `:ok` if within limits, `{:error, :rate_limited}` if exceeded.
  """
  @spec check_rate_limit(GenServer.server(), peer_id()) :: :ok | {:error, :rate_limited}
  def check_rate_limit(server \\ __MODULE__, peer_id) do
    GenServer.call(server, {:check_rate, peer_id})
  end

  @doc "Removes a peer from the scorer."
  @spec remove_peer(GenServer.server(), peer_id()) :: :ok
  def remove_peer(server \\ __MODULE__, peer_id) do
    GenServer.cast(server, {:remove, peer_id})
  end

  # --- GenServer callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, %__MODULE__{}}
  def init(_opts) do
    Process.send_after(self(), :decay, @decay_interval)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:success, peer_id, latency_ms}, state) do
    stats = get_or_init(state, peer_id)
    now = System.monotonic_time(:millisecond)

    stats = %{
      stats
      | successes: stats.successes + 1,
        total_latency_ms: stats.total_latency_ms + latency_ms,
        last_seen: now
    }

    stats = %{stats | score: compute_score(stats)}
    {:noreply, put_stats(state, peer_id, stats)}
  end

  def handle_cast({:failure, peer_id}, state) do
    stats = get_or_init(state, peer_id)
    now = System.monotonic_time(:millisecond)
    stats = %{stats | failures: stats.failures + 1, last_seen: now}
    stats = %{stats | score: compute_score(stats)}
    {:noreply, put_stats(state, peer_id, stats)}
  end

  def handle_cast({:timeout, peer_id}, state) do
    stats = get_or_init(state, peer_id)
    now = System.monotonic_time(:millisecond)
    stats = %{stats | timeouts: stats.timeouts + 1, last_seen: now}
    stats = %{stats | score: compute_score(stats)}
    {:noreply, put_stats(state, peer_id, stats)}
  end

  def handle_cast({:remove, peer_id}, state) do
    {:noreply, %{state | peers: Map.delete(state.peers, peer_id)}}
  end

  @impl true
  def handle_call({:get_score, peer_id}, _from, state) do
    score =
      case Map.get(state.peers, peer_id) do
        nil -> @base_score
        stats -> stats.score
      end

    {:reply, score, state}
  end

  def handle_call({:best_peers, count}, _from, state) do
    best =
      state.peers
      |> Enum.sort_by(fn {_id, stats} -> stats.score end, :desc)
      |> Enum.take(count)
      |> Enum.map(fn {id, stats} -> {id, stats.score} end)

    {:reply, best, state}
  end

  def handle_call(:bad_peers, _from, state) do
    bad =
      state.peers
      |> Enum.filter(fn {_id, stats} -> stats.score < @disconnect_threshold end)
      |> Enum.map(fn {id, _stats} -> id end)

    {:reply, bad, state}
  end

  def handle_call({:check_rate, peer_id}, _from, state) do
    now = System.monotonic_time(:millisecond)
    stats = get_or_init(state, peer_id)

    {result, stats} =
      if now - stats.window_start > @rate_window_ms do
        # New window
        {:ok, %{stats | message_count: 1, window_start: now}}
      else
        new_count = stats.message_count + 1

        if new_count > @max_messages_per_second do
          {{:error, :rate_limited}, stats}
        else
          {:ok, %{stats | message_count: new_count}}
        end
      end

    {:reply, result, put_stats(state, peer_id, stats)}
  end

  @impl true
  def handle_info(:decay, state) do
    peers =
      Map.new(state.peers, fn {id, stats} ->
        decayed_score =
          cond do
            stats.score > @base_score -> max(stats.score - @decay_amount, @base_score)
            stats.score < @base_score -> min(stats.score + @decay_amount, @base_score)
            true -> stats.score
          end

        {id, %{stats | score: decayed_score}}
      end)

    Process.send_after(self(), :decay, @decay_interval)
    {:noreply, %{state | peers: peers}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  @spec get_or_init(%__MODULE__{}, peer_id()) :: peer_stats()
  defp get_or_init(state, peer_id) do
    Map.get(state.peers, peer_id, %{
      score: @base_score,
      successes: 0,
      failures: 0,
      timeouts: 0,
      total_latency_ms: 0,
      last_seen: System.monotonic_time(:millisecond),
      message_count: 0,
      window_start: System.monotonic_time(:millisecond)
    })
  end

  @spec put_stats(%__MODULE__{}, peer_id(), peer_stats()) :: %__MODULE__{}
  defp put_stats(state, peer_id, stats) do
    %{state | peers: Map.put(state.peers, peer_id, stats)}
  end

  @spec compute_score(peer_stats()) :: float()
  defp compute_score(stats) do
    total = stats.successes + stats.failures + stats.timeouts
    success_rate = if total > 0, do: stats.successes / total, else: 0.5

    avg_latency =
      if stats.successes > 0, do: stats.total_latency_ms / stats.successes, else: 0

    @base_score + success_rate * 50 - avg_latency / 100 - stats.timeouts * 10 -
      stats.failures * 5
  end
end
