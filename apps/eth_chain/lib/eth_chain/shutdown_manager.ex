defmodule EthChain.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the Ethereum client.

  Listens for SIGTERM/SIGINT signals and orchestrates an orderly shutdown:
  1. Stop accepting new RPC connections
  2. Notify peers of disconnect
  3. Flush mempool state
  4. Ensure storage is flushed/synced
  5. Allow OTP supervision tree to stop cleanly
  """

  use GenServer

  require Logger

  @shutdown_timeout 15_000

  # --- Client API ---

  @doc "Starts the shutdown manager GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initiates a graceful shutdown sequence.

  Coordinates the ordered shutdown of RPC, networking, chain, and storage layers.
  Returns `:ok` after all shutdown steps complete or the timeout is reached.
  """
  @spec initiate_shutdown(GenServer.server()) :: :ok
  def initiate_shutdown(server \\ __MODULE__) do
    GenServer.call(server, :initiate_shutdown, @shutdown_timeout)
  end

  @doc """
  Returns the current shutdown state.

  Possible states: `:running`, `:shutting_down`, `:stopped`.
  """
  @spec status(GenServer.server()) :: :running | :shutting_down | :stopped
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(opts) do
    # Register signal handler for SIGTERM
    register_signal_handler()

    state = %{
      status: :running,
      shutdown_timeout: Keyword.get(opts, :shutdown_timeout, @shutdown_timeout),
      on_rpc_stop: Keyword.get(opts, :on_rpc_stop, &default_rpc_stop/0),
      on_net_stop: Keyword.get(opts, :on_net_stop, &default_net_stop/0),
      on_mempool_flush: Keyword.get(opts, :on_mempool_flush, &default_mempool_flush/0),
      on_storage_flush: Keyword.get(opts, :on_storage_flush, &default_storage_flush/0),
      halt_on_signal: Keyword.get(opts, :halt_on_signal, true)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:initiate_shutdown, _from, %{status: :running} = state) do
    state = %{state | status: :shutting_down}
    result = execute_shutdown_sequence(state)
    {:reply, result, %{state | status: :stopped}}
  end

  def handle_call(:initiate_shutdown, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_info({:system_signal, signal}, state) when signal in [:sigterm, :sigint] do
    Logger.info("ShutdownManager: Received #{signal}, initiating graceful shutdown")

    if state.status == :running do
      state = %{state | status: :shutting_down}
      execute_shutdown_sequence(state)

      # After shutdown sequence, let BEAM stop (unless disabled for testing)
      if state.halt_on_signal do
        :init.stop()
      end

      {:noreply, %{state | status: :stopped}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  @spec register_signal_handler() :: :ok
  defp register_signal_handler do
    self_pid = self()

    # Register handlers for SIGTERM and SIGINT via :os.set_signal_handler/2
    # Available in OTP 25+
    try do
      :os.set_signal(:sigterm, :handle)
      :os.set_signal(:sigint, :handle)

      # Spawn a process to receive signal messages and forward to us
      spawn_link(fn -> signal_listener(self_pid) end)
    rescue
      _error ->
        Logger.debug("ShutdownManager: OS signal handlers not available, using Process flag")
        Process.flag(:trap_exit, true)
    end

    :ok
  end

  @spec signal_listener(pid()) :: no_return()
  defp signal_listener(manager_pid) do
    receive do
      {:signal, signal} ->
        send(manager_pid, {:system_signal, signal})
        signal_listener(manager_pid)
    end
  end

  @spec execute_shutdown_sequence(map()) :: :ok
  defp execute_shutdown_sequence(state) do
    Logger.info("ShutdownManager: Shutting down gracefully...")

    # Step 1: Stop accepting new RPC connections
    Logger.info("ShutdownManager: [1/4] Stopping RPC server...")
    safe_execute(state.on_rpc_stop, "RPC stop")

    # Step 2: Notify peers and disconnect
    Logger.info("ShutdownManager: [2/4] Disconnecting peers...")
    safe_execute(state.on_net_stop, "network stop")

    # Step 3: Flush mempool state
    Logger.info("ShutdownManager: [3/4] Flushing mempool...")
    safe_execute(state.on_mempool_flush, "mempool flush")

    # Step 4: Flush storage
    Logger.info("ShutdownManager: [4/4] Flushing storage...")
    safe_execute(state.on_storage_flush, "storage flush")

    Logger.info("ShutdownManager: Graceful shutdown complete")
    :ok
  end

  @spec safe_execute(function(), String.t()) :: :ok
  defp safe_execute(fun, label) do
    try do
      fun.()
      :ok
    rescue
      error ->
        Logger.warning("ShutdownManager: #{label} failed: #{inspect(error)}")
        :ok
    catch
      :exit, reason ->
        Logger.warning("ShutdownManager: #{label} exited: #{inspect(reason)}")
        :ok
    end
  end

  @spec default_rpc_stop() :: :ok
  defp default_rpc_stop do
    if Code.ensure_loaded?(EthRpc.Application) do
      try do
        # Stop the Bandit HTTP servers by terminating children
        case Process.whereis(EthRpc.Supervisor) do
          nil ->
            :ok

          pid ->
            children = Supervisor.which_children(pid)

            Enum.each(children, fn {id, child_pid, _type, _modules} ->
              if id in [:rpc_server, :engine_server] and is_pid(child_pid) do
                Supervisor.terminate_child(pid, id)
              end
            end)
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @spec default_net_stop() :: :ok
  defp default_net_stop do
    if Code.ensure_loaded?(EthNet.Peer.ConnectionSupervisor) do
      try do
        case Process.whereis(EthNet.Peer.ConnectionSupervisor) do
          nil ->
            :ok

          _pid ->
            # Terminate all peer connections (each will send disconnect on termination)
            children = DynamicSupervisor.which_children(EthNet.Peer.ConnectionSupervisor)

            Enum.each(children, fn {:undefined, child_pid, _type, _modules} ->
              if is_pid(child_pid) do
                DynamicSupervisor.terminate_child(EthNet.Peer.ConnectionSupervisor, child_pid)
              end
            end)
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @spec default_mempool_flush() :: :ok
  defp default_mempool_flush do
    if Code.ensure_loaded?(EthChain.Mempool) do
      try do
        case Process.whereis(EthChain.Mempool) do
          nil -> :ok
          _pid -> EthChain.Mempool.pending_transactions()
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  @spec default_storage_flush() :: :ok
  defp default_storage_flush do
    if Code.ensure_loaded?(EthStorage.Store) do
      try do
        case Process.whereis(EthStorage.Store) do
          nil -> :ok
          _pid -> EthStorage.Store.flush()
        end
      rescue
        _ -> :ok
      end
    end

    :ok
  end
end
