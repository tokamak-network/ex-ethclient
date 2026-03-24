defmodule EthNet.Sync.Manager do
  @moduledoc """
  Coordinates block synchronization with peers.

  Tracks sync status, pending header/body requests, and downloaded data.
  Orchestrates the flow: request headers -> decode -> request bodies ->
  assemble blocks -> validate/execute -> store -> repeat until target reached.

  When the local head is far behind the target, the manager delegates to
  `EthNet.Sync.SnapSync` for fast state download before switching to
  full block-by-block sync.
  """

  use GenServer

  require Logger

  alias EthNet.Protocol.Eth68
  alias EthCore.Types.{Block, BlockHeader}
  alias EthNet.Sync.SnapSync

  # If we are this many blocks behind, use snap sync instead of full sync.
  @snap_sync_threshold 1024

  @type sync_status :: :idle | :snap_syncing | :syncing | :synced

  @batch_size 192
  @retry_delay 5_000

  defstruct status: :idle,
            target_block: 0,
            current_block: 0,
            pending_header_requests: %{},
            pending_body_requests: %{},
            downloaded_headers: [],
            downloaded_bodies: [],
            received_headers: %{},
            next_request_id: 1,
            block_pipeline: nil,
            store: nil,
            snap_sync_pid: nil

  @doc "Starts the Sync Manager."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Start syncing from current head to target block number.

  If the gap between current and target is larger than #{@snap_sync_threshold}
  blocks and a `pivot_root` is provided, snap sync is used. Otherwise falls
  back to full block-by-block sync.

  Accepts `opts` for dependency injection: `:server`, `:pivot_root`,
  `:block_pipeline`, `:store`.
  """
  @spec start_sync(non_neg_integer(), keyword()) :: :ok
  def start_sync(target_block, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.cast(server, {:start_sync, target_block, opts})
  end

  @doc "Returns current sync status."
  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Returns current sync status from a specific server."
  @spec status(GenServer.server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc "Handle received block headers from a peer."
  @spec handle_headers(pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_headers(peer, request_id, headers) do
    GenServer.cast(__MODULE__, {:headers, peer, request_id, headers})
  end

  @doc "Handle received block headers on a specific server."
  @spec handle_headers(GenServer.server(), pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_headers(server, peer, request_id, headers) do
    GenServer.cast(server, {:headers, peer, request_id, headers})
  end

  @doc "Handle received block bodies from a peer."
  @spec handle_bodies(pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_bodies(peer, request_id, bodies) do
    GenServer.cast(__MODULE__, {:bodies, peer, request_id, bodies})
  end

  @doc "Handle received block bodies on a specific server."
  @spec handle_bodies(GenServer.server(), pid(), non_neg_integer(), [binary()]) :: :ok
  def handle_bodies(server, peer, request_id, bodies) do
    GenServer.cast(server, {:bodies, peer, request_id, bodies})
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
  def init(opts) do
    state = %__MODULE__{
      block_pipeline: Keyword.get(opts, :block_pipeline),
      store: Keyword.get(opts, :store)
    }

    {:ok, state}
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
  def handle_cast({:start_sync, target_block, opts}, state) do
    gap = target_block - state.current_block
    pivot_root = Keyword.get(opts, :pivot_root)

    if gap >= @snap_sync_threshold and pivot_root != nil do
      Logger.info("Sync: Gap is #{gap} blocks, using snap sync")
      start_snap_sync(state, target_block, pivot_root)
    else
      Logger.info("Sync: Starting full sync to block #{target_block}")

      state = %{
        state
        | status: :syncing,
          target_block: target_block
      }

      send(self(), :request_headers)
      {:noreply, state}
    end
  end

  # Keep backward compatibility with the old 2-element cast
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

  def handle_cast({:start_sync, target_block, opts}, state) do
    Logger.info("Sync: Starting sync to block #{target_block}")

    state = %{
      state
      | status: :syncing,
        target_block: target_block,
        block_pipeline: Keyword.get(opts, :block_pipeline, state.block_pipeline),
        store: Keyword.get(opts, :store, state.store)
    }

    send(self(), :request_headers)
    {:noreply, state}
  end

  def handle_cast({:headers, peer, request_id, header_rlps}, state) do
    Logger.info(
      "Sync: Received #{length(header_rlps)} headers (req=#{request_id}) from #{inspect(peer)}"
    )

    case decode_headers(header_rlps) do
      {:ok, decoded_headers} ->
        state = %{
          state
          | downloaded_headers: state.downloaded_headers ++ decoded_headers,
            received_headers:
              Map.put(state.received_headers, request_id, decoded_headers),
            pending_header_requests:
              Map.delete(state.pending_header_requests, request_id)
        }

        # Request bodies for these headers
        if decoded_headers != [] do
          send(self(), {:request_bodies_for, request_id, peer})
        end

        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Sync: Failed to decode headers: #{inspect(reason)}")
        state = %{state | pending_header_requests: Map.delete(state.pending_header_requests, request_id)}
        {:noreply, state}
    end
  end

  def handle_cast({:bodies, _peer, request_id, bodies}, state) do
    Logger.info(
      "Sync: Received #{length(bodies)} bodies (req=#{request_id})"
    )

    case Map.fetch(state.pending_body_requests, request_id) do
      {:ok, {_peer, headers_request_id}} ->
        headers = Map.get(state.received_headers, headers_request_id, [])

        state = %{
          state
          | downloaded_bodies: state.downloaded_bodies ++ bodies,
            pending_body_requests: Map.delete(state.pending_body_requests, request_id)
        }

        send(self(), {:assemble_blocks, headers, bodies, headers_request_id})
        {:noreply, state}

      :error ->
        Logger.warning("Sync: Received bodies for unknown request #{request_id}")
        {:noreply, state}
    end
  end

  def handle_cast({:new_block, peer, block_info}, state) do
    Logger.info("Sync: New block announced by #{inspect(peer)}: #{inspect(block_info)}")

    # If we're synced and the new block extends our chain, update target
    state =
      case state.status do
        :synced ->
          case block_info do
            %{block_number: num} when is_integer(num) and num > state.current_block ->
              %{state | status: :syncing, target_block: num}

            _ ->
              state
          end

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_cast({:new_block_hashes, peer, hash_number_pairs}, state) do
    count = length(hash_number_pairs)
    Logger.info("Sync: #{count} new block hashes announced by #{inspect(peer)}")

    # Update target if any announced block is higher
    max_announced =
      hash_number_pairs
      |> Enum.map(fn {_hash, number} -> number end)
      |> Enum.max(fn -> 0 end)

    state =
      if max_announced > state.target_block and state.status in [:syncing, :synced] do
        %{state | target_block: max_announced, status: :syncing}
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:request_headers, %{status: :syncing} = state) do
    case get_best_peer() do
      nil ->
        Logger.warning("Sync: No peers available for header request")
        Process.send_after(self(), :request_headers, @retry_delay)
        {:noreply, state}

      peer ->
        request_id = state.next_request_id
        origin = state.current_block + 1
        amount = min(@batch_size, state.target_block - state.current_block)

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

  def handle_info({:request_bodies_for, headers_request_id, peer}, %{status: :syncing} = state) do
    headers = Map.get(state.received_headers, headers_request_id, [])

    if headers == [] do
      {:noreply, state}
    else
      request_id = state.next_request_id

      # Compute block hashes from headers for GetBlockBodies
      block_hashes = Enum.map(headers, &compute_block_hash/1)

      {code, payload} = Eth68.encode_get_block_bodies(request_id, block_hashes)
      send(peer, {:send_eth_message, code, payload})

      pending =
        Map.put(
          state.pending_body_requests,
          request_id,
          {peer, headers_request_id}
        )

      {:noreply, %{state | pending_body_requests: pending, next_request_id: request_id + 1}}
    end
  end

  def handle_info({:request_bodies_for, _headers_request_id, _peer}, state) do
    {:noreply, state}
  end

  def handle_info({:assemble_blocks, headers, bodies, headers_request_id}, state) do
    case assemble_and_process_blocks(state, headers, bodies) do
      {:ok, new_state} ->
        # Clean up received headers for this request
        new_state = %{
          new_state
          | received_headers: Map.delete(new_state.received_headers, headers_request_id)
        }

        # Continue syncing if not at target
        if new_state.current_block < new_state.target_block do
          send(self(), :request_headers)
          {:noreply, new_state}
        else
          Logger.info("Sync: Reached target block #{new_state.target_block}")
          {:noreply, %{new_state | status: :synced}}
        end

      {:error, reason, new_state} ->
        Logger.error("Sync: Block processing failed: #{inspect(reason)}")
        # Clean up and retry after delay
        new_state = %{
          new_state
          | received_headers: Map.delete(new_state.received_headers, headers_request_id)
        }

        Process.send_after(self(), :request_headers, @retry_delay)
        {:noreply, new_state}
    end
  end

  def handle_info(:request_bodies, %{status: :syncing} = state) do
    # Legacy handler - no-op since we now use {:request_bodies_for, ...}
    {:noreply, state}
  end

  def handle_info(:request_bodies, state) do
    {:noreply, state}
  end

  def handle_info(:check_sync_progress, state) do
    Logger.debug("Sync: Checking sync progress")
    {:noreply, state}
  end

  def handle_info(:check_snap_sync, %{status: :snap_syncing} = state) do
    case snap_sync_status(state) do
      :complete ->
        Logger.info("Sync: Snap sync complete, switching to full sync")

        state = %{
          state
          | status: :syncing,
            snap_sync_pid: nil
        }

        send(self(), :request_headers)
        {:noreply, state}

      _other ->
        Process.send_after(self(), :check_snap_sync, 1_000)
        {:noreply, state}
    end
  end

  def handle_info(:check_snap_sync, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private helpers ---

  @spec decode_headers([binary()]) :: {:ok, [BlockHeader.t()]} | {:error, term()}
  defp decode_headers(header_rlps) do
    results =
      Enum.reduce_while(header_rlps, {:ok, []}, fn header_rlp, {:ok, acc} ->
        case EthCore.RLP.decode_header(header_rlp) do
          {:ok, header} -> {:cont, {:ok, [header | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, headers} -> {:ok, Enum.reverse(headers)}
      {:error, _} = err -> err
    end
  end

  @spec assemble_and_process_blocks(struct(), [BlockHeader.t()], [term()]) ::
          {:ok, struct()} | {:error, term(), struct()}
  defp assemble_and_process_blocks(state, headers, bodies) do
    # Pad bodies with empty bodies if fewer bodies than headers
    # (some blocks may have empty bodies)
    padded_bodies = pad_bodies(bodies, length(headers))

    pairs = Enum.zip(headers, padded_bodies)

    Enum.reduce_while(pairs, {:ok, state}, fn {header, body}, {:ok, acc} ->
      block = assemble_block(header, body)

      case process_single_block(block, acc) do
        {:ok, new_state} ->
          {:cont, {:ok, new_state}}

        {:error, reason} ->
          {:halt, {:error, reason, acc}}
      end
    end)
    |> case do
      {:ok, _state} = result -> result
      {:error, reason, state} -> {:error, reason, state}
    end
  end

  @spec assemble_block(BlockHeader.t(), term()) :: Block.t()
  defp assemble_block(header, body) do
    {transactions, ommers, withdrawals} = parse_body(body)

    %Block{
      header: header,
      transactions: transactions,
      ommers: ommers,
      withdrawals: withdrawals
    }
  end

  @spec parse_body(term()) :: {list(), list(), list() | nil}
  defp parse_body([transactions, ommers]) do
    {transactions, ommers, nil}
  end

  defp parse_body([transactions, ommers, withdrawals]) do
    {transactions, ommers, withdrawals}
  end

  defp parse_body(_) do
    {[], [], nil}
  end

  @spec pad_bodies([term()], non_neg_integer()) :: [term()]
  defp pad_bodies(bodies, count) when length(bodies) >= count, do: bodies

  defp pad_bodies(bodies, count) do
    padding = List.duplicate([[], []], count - length(bodies))
    bodies ++ padding
  end

  @spec process_single_block(Block.t(), struct()) ::
          {:ok, struct()} | {:error, term()}
  defp process_single_block(block, state) do
    pipeline = state.block_pipeline || EthChain.BlockPipeline
    store = state.store

    case apply_block_pipeline(pipeline, block, store) do
      {:ok, _hash} ->
        Logger.info("Sync: Processed block ##{block.header.number}")
        {:ok, %{state | current_block: block.header.number}}

      {:error, reason} ->
        Logger.warning(
          "Sync: Failed to process block ##{block.header.number}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec apply_block_pipeline(module() | function(), Block.t(), term()) ::
          {:ok, binary()} | {:error, term()}
  defp apply_block_pipeline(pipeline, block, store) when is_function(pipeline, 2) do
    pipeline.(block, store)
  end

  defp apply_block_pipeline(pipeline, block, store) when is_atom(pipeline) do
    pipeline.process_new_block(block, store)
  end

  @spec compute_block_hash(BlockHeader.t()) :: <<_::256>>
  defp compute_block_hash(%BlockHeader{} = header) do
    header
    |> EthCore.RLP.encode_header()
    |> EthCrypto.Hash.keccak256()
  end

  defp get_best_peer do
    peers = EthNet.Peer.Manager.connected_peers()

    case peers do
      [] -> nil
      [first | _] -> Map.get(first, :pid)
    end
  catch
    :exit, _ -> nil
  end

  defp start_snap_sync(state, target_block, pivot_root) do
    case SnapSync.start_link(name: SnapSync) do
      {:ok, pid} ->
        SnapSync.start_sync(SnapSync, target_block, pivot_root)
        Process.send_after(self(), :check_snap_sync, 1_000)

        {:noreply,
         %{state | status: :snap_syncing, target_block: target_block, snap_sync_pid: pid}}

      {:error, {:already_started, pid}} ->
        SnapSync.start_sync(SnapSync, target_block, pivot_root)
        Process.send_after(self(), :check_snap_sync, 1_000)

        {:noreply,
         %{state | status: :snap_syncing, target_block: target_block, snap_sync_pid: pid}}

      {:error, reason} ->
        Logger.warning("Sync: Failed to start snap sync: #{inspect(reason)}, falling back")

        state = %{state | status: :syncing, target_block: target_block}
        send(self(), :request_headers)
        {:noreply, state}
    end
  end

  defp snap_sync_status(state) do
    if state.snap_sync_pid && Process.alive?(state.snap_sync_pid) do
      info = SnapSync.status(SnapSync)
      info.status
    else
      :complete
    end
  rescue
    _ -> :complete
  end
end
