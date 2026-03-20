defmodule EthNet.Sync.Manager do
  @moduledoc """
  Coordinates block synchronization with peers.

  Tracks sync status, pending header/body requests, and downloaded data.
  Orchestrates the flow: request headers -> validate -> request bodies ->
  assemble blocks -> repeat until target reached.
  """

  use GenServer

  require Logger

  alias EthNet.Protocol.Eth68

  @type sync_status :: :idle | :syncing | :synced

  defstruct status: :idle,
            target_block: 0,
            current_block: 0,
            pending_header_requests: %{},
            pending_body_requests: %{},
            downloaded_headers: [],
            downloaded_bodies: [],
            next_request_id: 1

  @doc "Starts the Sync Manager."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start syncing from current head to target block number."
  @spec start_sync(non_neg_integer()) :: :ok
  def start_sync(target_block) do
    GenServer.cast(__MODULE__, {:start_sync, target_block})
  end

  @doc "Returns current sync status."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Handle received block headers from a peer."
  @spec handle_headers(pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_headers(peer, request_id, headers) do
    GenServer.cast(__MODULE__, {:headers, peer, request_id, headers})
  end

  @doc "Handle received block bodies from a peer."
  @spec handle_bodies(pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_bodies(peer, request_id, bodies) do
    GenServer.cast(__MODULE__, {:bodies, peer, request_id, bodies})
  end

  @doc "Handle a new block announcement from a peer."
  @spec handle_new_block(pid(), map()) :: :ok
  def handle_new_block(peer, block_info) do
    GenServer.cast(__MODULE__, {:new_block, peer, block_info})
  end

  @doc "Handle new block hash announcements from a peer."
  @spec handle_new_block_hashes(pid(), [{binary(), non_neg_integer()}]) :: :ok
  def handle_new_block_hashes(peer, hash_number_pairs) do
    GenServer.cast(__MODULE__, {:new_block_hashes, peer, hash_number_pairs})
  end

  # --- Server callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    info = %{
      status: state.status,
      target_block: state.target_block,
      current_block: state.current_block,
      pending_headers: map_size(state.pending_header_requests),
      pending_bodies: map_size(state.pending_body_requests),
      downloaded_headers: length(state.downloaded_headers),
      downloaded_bodies: length(state.downloaded_bodies)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:start_sync, target_block}, state) do
    Logger.info("Sync: Starting sync to block #{target_block}")

    state = %{
      state
      | status: :syncing,
        target_block: target_block
    }

    send(self(), :request_headers)
    {:noreply, state}
  end

  def handle_cast({:headers, peer, request_id, headers}, state) do
    Logger.info(
      "Sync: Received #{length(headers)} headers (req=#{request_id}) from #{inspect(peer)}"
    )

    state = %{
      state
      | downloaded_headers: state.downloaded_headers ++ headers,
        pending_header_requests: Map.delete(state.pending_header_requests, request_id)
    }

    # If we have headers, request their bodies
    if headers != [] do
      send(self(), :request_bodies)
    end

    {:noreply, state}
  end

  def handle_cast({:bodies, peer, request_id, bodies}, state) do
    Logger.info(
      "Sync: Received #{length(bodies)} bodies (req=#{request_id}) from #{inspect(peer)}"
    )

    state = %{
      state
      | downloaded_bodies: state.downloaded_bodies ++ bodies,
        pending_body_requests: Map.delete(state.pending_body_requests, request_id)
    }

    send(self(), :check_sync_progress)
    {:noreply, state}
  end

  def handle_cast({:new_block, peer, block_info}, state) do
    Logger.info("Sync: New block announced by #{inspect(peer)}: #{inspect(block_info)}")
    {:noreply, state}
  end

  def handle_cast({:new_block_hashes, peer, hash_number_pairs}, state) do
    count = length(hash_number_pairs)
    Logger.info("Sync: #{count} new block hashes announced by #{inspect(peer)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:request_headers, %{status: :syncing} = state) do
    case get_best_peer() do
      nil ->
        Logger.warning("Sync: No peers available for header request")
        Process.send_after(self(), :request_headers, 5_000)
        {:noreply, state}

      peer ->
        request_id = state.next_request_id
        origin = state.current_block + 1
        amount = min(192, state.target_block - state.current_block)

        if amount > 0 do
          {code, payload} = Eth68.encode_get_block_headers(request_id, origin, amount, 0, false)

          send(peer, {:send_eth_message, code, payload})

          pending = Map.put(state.pending_header_requests, request_id, {peer, origin, amount})

          {:noreply, %{state | pending_header_requests: pending, next_request_id: request_id + 1}}
        else
          Logger.info("Sync: Reached target block #{state.target_block}")
          {:noreply, %{state | status: :synced}}
        end
    end
  end

  def handle_info(:request_headers, state) do
    {:noreply, state}
  end

  def handle_info(:request_bodies, %{status: :syncing} = state) do
    # In a real implementation, we'd extract block hashes from headers
    # and request the corresponding bodies
    Logger.debug("Sync: Would request block bodies for downloaded headers")
    {:noreply, state}
  end

  def handle_info(:request_bodies, state) do
    {:noreply, state}
  end

  def handle_info(:check_sync_progress, state) do
    Logger.debug("Sync: Checking sync progress")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private helpers ---

  defp get_best_peer do
    peers = EthNet.Peer.Manager.connected_peers()

    case peers do
      [] -> nil
      [first | _] -> Map.get(first, :pid)
    end
  catch
    :exit, _ -> nil
  end
end
