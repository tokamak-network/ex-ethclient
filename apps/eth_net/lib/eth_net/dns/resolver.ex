defmodule EthNet.DNS.Resolver do
  @moduledoc """
  GenServer that periodically discovers peers via EIP-1459 DNS discovery.

  Takes a list of DNS tree URLs of the form:

      enrtree://<base32-pubkey>@<domain>

  Resolves DNS TXT records to walk the Merkle tree of ENR records,
  decoding each into peer connection information (IP, port, node ID).

  ## Configuration

      config :eth_net,
        dns_discovery: true,
        dns_seeds: [
          "enrtree://AKA3AM6LPBYEUDMVNU3BSVQJ5AD45Y7YPOHJLEF6W26QOE4VTUDPE@all.mainnet.ethdisco.net"
        ],
        dns_sync_interval: 1_800_000  # 30 minutes
  """

  use GenServer

  require Logger

  alias EthNet.DNS.{Sync, Tree}

  @default_sync_interval 1_800_000
  @default_seeds [
    "enrtree://AKA3AM6LPBYEUDMVNU3BSVQJ5AD45Y7YPOHJLEF6W26QOE4VTUDPE@all.mainnet.ethdisco.net"
  ]

  defstruct [
    :sync_interval,
    seeds: [],
    peers: [],
    cache: %{},
    syncing: false
  ]

  # --- Public API ---

  @doc "Starts the DNS resolver GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the list of discovered peers."
  @spec peers() :: [Sync.peer_info()]
  def peers do
    GenServer.call(__MODULE__, :peers)
  end

  @doc "Triggers an immediate re-sync of all DNS trees."
  @spec sync() :: :ok
  def sync do
    GenServer.cast(__MODULE__, :sync)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    seeds = Keyword.get(opts, :seeds, @default_seeds)
    sync_interval = Keyword.get(opts, :sync_interval, @default_sync_interval)

    state = %__MODULE__{
      seeds: seeds,
      sync_interval: sync_interval
    }

    # Schedule initial sync after a short delay
    Process.send_after(self(), :do_sync, 1_000)

    Logger.info("DNS: Resolver started with #{length(seeds)} seed(s)")

    {:ok, state}
  end

  @impl true
  def handle_call(:peers, _from, state) do
    {:reply, state.peers, state}
  end

  @impl true
  def handle_cast(:sync, state) do
    send(self(), :do_sync)
    {:noreply, state}
  end

  @impl true
  def handle_info(:do_sync, %{syncing: true} = state) do
    {:noreply, state}
  end

  def handle_info(:do_sync, state) do
    state = %{state | syncing: true}

    {peers, cache} =
      Enum.reduce(state.seeds, {[], state.cache}, fn seed_url, {acc_peers, acc_cache} ->
        case Tree.parse_link(seed_url) do
          {:ok, %{pubkey: pubkey, domain: domain}} ->
            case Sync.sync(domain, pubkey, cache: acc_cache) do
              {:ok, new_peers, new_cache} ->
                Logger.info("DNS: Discovered #{length(new_peers)} peer(s) from #{domain}")
                {acc_peers ++ new_peers, new_cache}

              {:error, reason} ->
                Logger.warning("DNS: Failed to sync #{domain}: #{inspect(reason)}")
                {acc_peers, acc_cache}
            end

          {:error, reason} ->
            Logger.warning("DNS: Invalid seed URL #{seed_url}: #{inspect(reason)}")
            {acc_peers, acc_cache}
        end
      end)

    # Deduplicate by node_id
    unique_peers = deduplicate_peers(peers)

    Logger.info("DNS: Total unique peers discovered: #{length(unique_peers)}")

    # Schedule next sync
    Process.send_after(self(), :do_sync, state.sync_interval)

    {:noreply, %{state | peers: unique_peers, cache: cache, syncing: false}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private helpers ---

  defp deduplicate_peers(peers) do
    peers
    |> Enum.uniq_by(& &1.node_id)
  end
end
