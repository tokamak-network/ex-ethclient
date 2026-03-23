defmodule EthNet.Sync.SnapSync do
  @moduledoc """
  Snap sync state machine for fast state download.

  Downloads the Ethereum state trie in ranges using the snap/1 protocol
  rather than block-by-block. The state machine progresses through phases:

  1. Select pivot block (recent finalized block)
  2. Download account ranges from peers via snap/1
  3. Download storage ranges for accounts with storage
  4. Download contract bytecodes
  5. Heal: fill missing trie nodes
  6. Switch to full sync once state is complete
  """

  use GenServer

  require Logger

  import Bitwise

  alias EthNet.Protocol.Snap1

  @type sync_status ::
          :idle
          | :downloading_accounts
          | :downloading_storage
          | :downloading_codes
          | :healing
          | :complete

  @type request_type :: :account_range | :storage_ranges | :byte_codes | :trie_nodes

  @type t :: %__MODULE__{
          status: sync_status(),
          pivot_block: non_neg_integer() | nil,
          pivot_root: binary() | nil,
          account_start: binary(),
          account_limit: binary(),
          accounts_downloaded: non_neg_integer(),
          pending_storage: [binary()],
          storage_downloaded: non_neg_integer(),
          pending_codes: [binary()],
          codes_downloaded: non_neg_integer(),
          pending_trie_nodes: [list()],
          nodes_healed: non_neg_integer(),
          pending_requests: %{non_neg_integer() => {request_type(), pid(), integer()}},
          next_request_id: non_neg_integer(),
          peers: [pid()]
        }

  @max_hash <<255::unsigned-size(256)>>
  @response_bytes 512 * 1024
  @batch_size 256

  @empty_trie_root EthCore.Types.Account.empty_trie_root()
  @empty_code_hash EthCore.Types.Account.empty_code_hash()

  defstruct status: :idle,
            pivot_block: nil,
            pivot_root: nil,
            account_start: <<0::256>>,
            account_limit: @max_hash,
            accounts_downloaded: 0,
            pending_storage: [],
            storage_downloaded: 0,
            pending_codes: [],
            codes_downloaded: 0,
            pending_trie_nodes: [],
            nodes_healed: 0,
            pending_requests: %{},
            next_request_id: 1,
            peers: []

  # --- Public API ---

  @doc "Starts the SnapSync GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initiates snap sync with the given pivot block number and state root.

  Transitions from :idle to :downloading_accounts and begins
  requesting account ranges from available peers.
  """
  @spec start_sync(GenServer.server(), non_neg_integer(), binary()) :: :ok
  def start_sync(server \\ __MODULE__, pivot_block, pivot_root) do
    GenServer.cast(server, {:start_sync, pivot_block, pivot_root})
  end

  @doc "Returns the current snap sync status as a map."
  @spec status(GenServer.server()) :: map()
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc "Handles an AccountRange response from a peer."
  @spec handle_account_range(GenServer.server(), non_neg_integer(), list(), [binary()]) :: :ok
  def handle_account_range(server \\ __MODULE__, request_id, accounts, proof) do
    GenServer.cast(server, {:account_range, request_id, accounts, proof})
  end

  @doc "Handles a StorageRanges response from a peer."
  @spec handle_storage_ranges(GenServer.server(), non_neg_integer(), list(), [binary()]) :: :ok
  def handle_storage_ranges(server \\ __MODULE__, request_id, slots, proof) do
    GenServer.cast(server, {:storage_ranges, request_id, slots, proof})
  end

  @doc "Handles a ByteCodes response from a peer."
  @spec handle_byte_codes(GenServer.server(), non_neg_integer(), [binary()]) :: :ok
  def handle_byte_codes(server \\ __MODULE__, request_id, codes) do
    GenServer.cast(server, {:byte_codes, request_id, codes})
  end

  @doc "Handles a TrieNodes response from a peer."
  @spec handle_trie_nodes(GenServer.server(), non_neg_integer(), [binary()]) :: :ok
  def handle_trie_nodes(server \\ __MODULE__, request_id, nodes) do
    GenServer.cast(server, {:trie_nodes, request_id, nodes})
  end

  @doc "Adds a peer to the snap sync peer list."
  @spec add_peer(GenServer.server(), pid()) :: :ok
  def add_peer(server \\ __MODULE__, peer_pid) do
    GenServer.cast(server, {:add_peer, peer_pid})
  end

  @doc "Removes a peer from the snap sync peer list."
  @spec remove_peer(GenServer.server(), pid()) :: :ok
  def remove_peer(server \\ __MODULE__, peer_pid) do
    GenServer.cast(server, {:remove_peer, peer_pid})
  end

  # --- GenServer callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, t()}
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    info = %{
      status: state.status,
      pivot_block: state.pivot_block,
      pivot_root: state.pivot_root,
      accounts_downloaded: state.accounts_downloaded,
      storage_downloaded: state.storage_downloaded,
      codes_downloaded: state.codes_downloaded,
      nodes_healed: state.nodes_healed,
      pending_storage: length(state.pending_storage),
      pending_codes: length(state.pending_codes),
      pending_trie_nodes: length(state.pending_trie_nodes),
      pending_requests: map_size(state.pending_requests),
      peers: length(state.peers)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:start_sync, pivot_block, pivot_root}, %{status: :idle} = state) do
    Logger.info("SnapSync: Starting snap sync at pivot block #{pivot_block}")

    state = %{
      state
      | status: :downloading_accounts,
        pivot_block: pivot_block,
        pivot_root: pivot_root,
        account_start: <<0::256>>
    }

    send(self(), :request_next)
    {:noreply, state}
  end

  def handle_cast({:start_sync, _pivot_block, _pivot_root}, state) do
    Logger.warning("SnapSync: Cannot start sync, current status: #{state.status}")
    {:noreply, state}
  end

  def handle_cast({:account_range, request_id, accounts, _proof}, state) do
    state = complete_request(state, request_id)
    state = process_account_range(state, accounts)

    state =
      if accounts == [] or reached_limit?(state) do
        transition_from_accounts(state)
      else
        send(self(), :request_next)
        state
      end

    {:noreply, state}
  end

  def handle_cast({:storage_ranges, request_id, slots, _proof}, state) do
    state = complete_request(state, request_id)
    state = process_storage_ranges(state, slots)
    state = check_phase_complete(state)
    {:noreply, state}
  end

  def handle_cast({:byte_codes, request_id, codes}, state) do
    state = complete_request(state, request_id)
    state = process_byte_codes(state, codes)
    state = check_phase_complete(state)
    {:noreply, state}
  end

  def handle_cast({:trie_nodes, request_id, nodes}, state) do
    state = complete_request(state, request_id)
    state = process_trie_nodes(state, nodes)
    state = check_phase_complete(state)
    {:noreply, state}
  end

  def handle_cast({:add_peer, peer_pid}, state) do
    if peer_pid in state.peers do
      {:noreply, state}
    else
      {:noreply, %{state | peers: [peer_pid | state.peers]}}
    end
  end

  def handle_cast({:remove_peer, peer_pid}, state) do
    {:noreply, %{state | peers: List.delete(state.peers, peer_pid)}}
  end

  @impl true
  def handle_info(:request_next, %{status: :downloading_accounts} = state) do
    state = request_next_account_range(state)
    {:noreply, state}
  end

  def handle_info(:request_next, %{status: :downloading_storage} = state) do
    state = request_storage_ranges(state)
    {:noreply, state}
  end

  def handle_info(:request_next, %{status: :downloading_codes} = state) do
    state = request_byte_codes(state)
    {:noreply, state}
  end

  def handle_info(:request_next, %{status: :healing} = state) do
    state = request_trie_nodes(state)
    {:noreply, state}
  end

  def handle_info(:request_next, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private: request helpers ---

  @spec request_next_account_range(t()) :: t()
  defp request_next_account_range(state) do
    case pick_peer(state) do
      nil ->
        Logger.warning("SnapSync: No peers available for account range request")
        Process.send_after(self(), :request_next, 5_000)
        state

      peer ->
        request_id = state.next_request_id

        {_code, _payload} =
          Snap1.encode_get_account_range(
            request_id,
            state.pivot_root,
            state.account_start,
            state.account_limit,
            @response_bytes
          )

        Logger.debug("SnapSync: Requesting account range (req=#{request_id})")

        pending =
          Map.put(
            state.pending_requests,
            request_id,
            {:account_range, peer, System.monotonic_time(:millisecond)}
          )

        %{state | pending_requests: pending, next_request_id: request_id + 1}
    end
  end

  @spec request_storage_ranges(t()) :: t()
  defp request_storage_ranges(state) do
    case {pick_peer(state), state.pending_storage} do
      {nil, _} ->
        Logger.warning("SnapSync: No peers available for storage range request")
        Process.send_after(self(), :request_next, 5_000)
        state

      {_, []} ->
        state

      {peer, pending} ->
        request_id = state.next_request_id
        batch = Enum.take(pending, @batch_size)
        remaining = Enum.drop(pending, @batch_size)

        {_code, _payload} =
          Snap1.encode_get_storage_ranges(
            request_id,
            state.pivot_root,
            batch,
            <<0::256>>,
            @max_hash,
            @response_bytes
          )

        Logger.debug(
          "SnapSync: Requesting storage ranges for #{length(batch)} accounts (req=#{request_id})"
        )

        pending_reqs =
          Map.put(
            state.pending_requests,
            request_id,
            {:storage_ranges, peer, System.monotonic_time(:millisecond)}
          )

        %{
          state
          | pending_requests: pending_reqs,
            pending_storage: remaining,
            next_request_id: request_id + 1
        }
    end
  end

  @spec request_byte_codes(t()) :: t()
  defp request_byte_codes(state) do
    case {pick_peer(state), state.pending_codes} do
      {nil, _} ->
        Logger.warning("SnapSync: No peers available for byte codes request")
        Process.send_after(self(), :request_next, 5_000)
        state

      {_, []} ->
        state

      {peer, pending} ->
        request_id = state.next_request_id
        batch = Enum.take(pending, @batch_size)
        remaining = Enum.drop(pending, @batch_size)

        {_code, _payload} =
          Snap1.encode_get_byte_codes(request_id, batch, @response_bytes)

        Logger.debug(
          "SnapSync: Requesting #{length(batch)} byte codes (req=#{request_id})"
        )

        pending_reqs =
          Map.put(
            state.pending_requests,
            request_id,
            {:byte_codes, peer, System.monotonic_time(:millisecond)}
          )

        %{
          state
          | pending_requests: pending_reqs,
            pending_codes: remaining,
            next_request_id: request_id + 1
        }
    end
  end

  @spec request_trie_nodes(t()) :: t()
  defp request_trie_nodes(state) do
    case {pick_peer(state), state.pending_trie_nodes} do
      {nil, _} ->
        Logger.warning("SnapSync: No peers available for trie nodes request")
        Process.send_after(self(), :request_next, 5_000)
        state

      {_, []} ->
        state

      {peer, pending} ->
        request_id = state.next_request_id
        batch = Enum.take(pending, @batch_size)
        remaining = Enum.drop(pending, @batch_size)

        {_code, _payload} =
          Snap1.encode_get_trie_nodes(request_id, state.pivot_root, batch, @response_bytes)

        Logger.debug(
          "SnapSync: Requesting #{length(batch)} trie nodes (req=#{request_id})"
        )

        pending_reqs =
          Map.put(
            state.pending_requests,
            request_id,
            {:trie_nodes, peer, System.monotonic_time(:millisecond)}
          )

        %{
          state
          | pending_requests: pending_reqs,
            pending_trie_nodes: remaining,
            next_request_id: request_id + 1
        }
    end
  end

  # --- Private: response processing ---

  @spec process_account_range(t(), list()) :: t()
  defp process_account_range(state, accounts) do
    {new_storage, new_codes, last_hash} =
      Enum.reduce(accounts, {state.pending_storage, state.pending_codes, state.account_start},
        fn {hash, _nonce, _balance, storage_root, code_hash}, {stor, codes, _last} ->
          stor = if storage_root != @empty_trie_root, do: [hash | stor], else: stor
          codes = if code_hash != @empty_code_hash, do: [code_hash | codes], else: codes
          {stor, codes, hash}
        end
      )

    # Advance account_start past the last received hash
    next_start = increment_hash(last_hash)

    %{
      state
      | accounts_downloaded: state.accounts_downloaded + length(accounts),
        pending_storage: new_storage,
        pending_codes: new_codes,
        account_start: next_start
    }
  end

  @spec process_storage_ranges(t(), list()) :: t()
  defp process_storage_ranges(state, slots) do
    total = Enum.reduce(slots, 0, fn account_slots, acc -> acc + length(account_slots) end)

    %{state | storage_downloaded: state.storage_downloaded + total}
  end

  @spec process_byte_codes(t(), [binary()]) :: t()
  defp process_byte_codes(state, codes) do
    %{state | codes_downloaded: state.codes_downloaded + length(codes)}
  end

  @spec process_trie_nodes(t(), [binary()]) :: t()
  defp process_trie_nodes(state, nodes) do
    %{state | nodes_healed: state.nodes_healed + length(nodes)}
  end

  # --- Private: state transitions ---

  @spec transition_from_accounts(t()) :: t()
  defp transition_from_accounts(state) do
    Logger.info(
      "SnapSync: Account download complete (#{state.accounts_downloaded} accounts)"
    )

    if state.pending_storage != [] do
      Logger.info(
        "SnapSync: Transitioning to storage download (#{length(state.pending_storage)} accounts)"
      )

      state = %{state | status: :downloading_storage}
      send(self(), :request_next)
      state
    else
      transition_from_storage(state)
    end
  end

  @spec transition_from_storage(t()) :: t()
  defp transition_from_storage(state) do
    if state.pending_codes != [] do
      Logger.info(
        "SnapSync: Transitioning to code download (#{length(state.pending_codes)} codes)"
      )

      state = %{state | status: :downloading_codes}
      send(self(), :request_next)
      state
    else
      transition_from_codes(state)
    end
  end

  @spec transition_from_codes(t()) :: t()
  defp transition_from_codes(state) do
    if state.pending_trie_nodes != [] do
      Logger.info(
        "SnapSync: Transitioning to healing (#{length(state.pending_trie_nodes)} nodes)"
      )

      state = %{state | status: :healing}
      send(self(), :request_next)
      state
    else
      Logger.info("SnapSync: Sync complete!")
      %{state | status: :complete}
    end
  end

  @spec check_phase_complete(t()) :: t()
  defp check_phase_complete(%{status: :downloading_storage} = state) do
    has_pending_storage_requests? =
      Enum.any?(state.pending_requests, fn {_id, {type, _, _}} -> type == :storage_ranges end)

    if state.pending_storage == [] and not has_pending_storage_requests? do
      transition_from_storage(state)
    else
      if state.pending_storage != [] do
        send(self(), :request_next)
      end

      state
    end
  end

  defp check_phase_complete(%{status: :downloading_codes} = state) do
    has_pending_code_requests? =
      Enum.any?(state.pending_requests, fn {_id, {type, _, _}} -> type == :byte_codes end)

    if state.pending_codes == [] and not has_pending_code_requests? do
      transition_from_codes(state)
    else
      if state.pending_codes != [] do
        send(self(), :request_next)
      end

      state
    end
  end

  defp check_phase_complete(%{status: :healing} = state) do
    has_pending_heal_requests? =
      Enum.any?(state.pending_requests, fn {_id, {type, _, _}} -> type == :trie_nodes end)

    if state.pending_trie_nodes == [] and not has_pending_heal_requests? do
      Logger.info("SnapSync: Healing complete, sync finished!")
      %{state | status: :complete}
    else
      if state.pending_trie_nodes != [] do
        send(self(), :request_next)
      end

      state
    end
  end

  defp check_phase_complete(state), do: state

  # --- Private: utilities ---

  @spec complete_request(t(), non_neg_integer()) :: t()
  defp complete_request(state, request_id) do
    %{state | pending_requests: Map.delete(state.pending_requests, request_id)}
  end

  @spec pick_peer(t()) :: pid() | nil
  defp pick_peer(%{peers: []}), do: nil
  defp pick_peer(%{peers: peers}), do: Enum.random(peers)

  @spec reached_limit?(t()) :: boolean()
  defp reached_limit?(%{account_start: start, account_limit: limit}) do
    start >= limit
  end

  @spec increment_hash(binary()) :: binary()
  defp increment_hash(<<val::unsigned-big-256>>) do
    new_val = val + 1

    if new_val >= bsl(1, 256) do
      @max_hash
    else
      <<new_val::unsigned-big-256>>
    end
  end

  defp increment_hash(other), do: other
end
