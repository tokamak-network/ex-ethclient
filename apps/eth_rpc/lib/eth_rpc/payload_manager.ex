defmodule EthRpc.PayloadManager do
  @moduledoc "Manages block payloads for the Engine API."

  use GenServer

  @type payload_data :: %{
          params: map(),
          status: :building | :ready,
          result: term()
        }

  # --- Public API ---

  @doc "Starts the payload manager."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Creates a new payload build task. Returns a payload_id.

  Accepts a map with keys like parent_hash, timestamp, coinbase, etc.
  """
  @spec new_payload(map(), GenServer.server()) ::
          {:ok, non_neg_integer()}
  def new_payload(params, server \\ __MODULE__) do
    GenServer.call(server, {:new_payload, params})
  end

  @doc "Gets a built payload by ID."
  @spec get_payload(non_neg_integer(), GenServer.server()) ::
          {:ok, map()} | {:error, :not_found}
  def get_payload(payload_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_payload, payload_id})
  end

  @doc "Stores a payload that was validated via newPayload."
  @spec store_validated_payload(map(), GenServer.server()) :: :ok
  def store_validated_payload(payload, server \\ __MODULE__) do
    GenServer.call(server, {:store_validated, payload})
  end

  # --- GenServer Callbacks ---

  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts) do
    {:ok, %{payloads: %{}, next_id: 1}}
  end

  @impl true
  def handle_call({:new_payload, params}, _from, state) do
    id = state.next_id

    payload_data = %{
      params: params,
      status: :ready,
      result: nil
    }

    new_payloads = Map.put(state.payloads, id, payload_data)
    new_state = %{state | payloads: new_payloads, next_id: id + 1}
    {:reply, {:ok, id}, new_state}
  end

  @impl true
  def handle_call({:get_payload, id}, _from, state) do
    case Map.fetch(state.payloads, id) do
      {:ok, payload} -> {:reply, {:ok, payload}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:store_validated, payload}, _from, state) do
    id = state.next_id

    payload_data = %{
      params: payload,
      status: :ready,
      result: :validated
    }

    new_payloads = Map.put(state.payloads, id, payload_data)
    new_state = %{state | payloads: new_payloads, next_id: id + 1}
    {:reply, :ok, new_state}
  end
end
