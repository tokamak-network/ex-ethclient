defmodule EthChain.BeaconFetcher do
  @moduledoc """
  Fetches execution payloads from a public Beacon API endpoint.
  Replaces the need for a local Consensus Layer client (e.g., Lighthouse).

  Polls the Beacon API every slot (12 seconds) for new blocks
  and feeds them into the Engine API pipeline via internal function calls.

  ## Usage

      EthChain.BeaconFetcher.start_link(
        endpoint: "https://ethereum-sepolia-beacon-api.publicnode.com",
        network: :sepolia
      )

  """

  use GenServer

  require Logger

  @slot_time 12_000
  @default_endpoint "https://ethereum-sepolia-beacon-api.publicnode.com"
  @initial_delay 2_000
  @http_timeout 10_000
  @connect_timeout 5_000

  @type status :: %{
          last_slot: non_neg_integer(),
          last_block_number: non_neg_integer(),
          endpoint: String.t(),
          network: atom(),
          errors: non_neg_integer(),
          running: boolean()
        }

  defstruct endpoint: @default_endpoint,
            last_slot: 0,
            last_block_number: 0,
            network: :sepolia,
            running: true,
            errors: 0

  # --- Public API ---

  @doc "Starts the BeaconFetcher GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the current status of the BeaconFetcher."
  @spec status() :: status()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc "Stops the BeaconFetcher."
  @spec stop() :: :ok
  def stop do
    GenServer.stop(__MODULE__)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    endpoint = Keyword.get(opts, :endpoint, @default_endpoint)
    network = Keyword.get(opts, :network, :sepolia)

    ensure_http_client_started()

    Logger.info("BeaconFetcher: starting, endpoint=#{endpoint}, network=#{network}")

    Process.send_after(self(), :fetch_head, @initial_delay)

    {:ok, %__MODULE__{endpoint: endpoint, network: network}}
  end

  @impl true
  def handle_info(:fetch_head, state) do
    state = fetch_and_process_head(state)
    Process.send_after(self(), :fetch_head, @slot_time)
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      last_slot: state.last_slot,
      last_block_number: state.last_block_number,
      endpoint: state.endpoint,
      network: state.network,
      errors: state.errors,
      running: state.running
    }

    {:reply, reply, state}
  end

  # --- Fetch logic ---

  @spec fetch_and_process_head(%__MODULE__{}) :: %__MODULE__{}
  defp fetch_and_process_head(state) do
    case fetch_head_block(state.endpoint) do
      {:ok, slot, exec_payload} ->
        if slot > state.last_slot do
          Logger.info("BeaconFetcher: new block at slot #{slot}")
          state = process_execution_payload(exec_payload, state)
          %{state | last_slot: slot, errors: 0}
        else
          state
        end

      {:error, reason} ->
        Logger.warning("BeaconFetcher: failed to fetch head: #{inspect(reason)}")
        %{state | errors: state.errors + 1}
    end
  end

  @doc false
  @spec fetch_head_block(String.t()) ::
          {:ok, non_neg_integer(), map()} | {:error, term()}
  def fetch_head_block(endpoint) do
    url = "#{endpoint}/eth/v2/beacon/blocks/head"
    headers = [{~c"Accept", ~c"application/json"}]

    http_opts = [
      {:timeout, @http_timeout},
      {:connect_timeout, @connect_timeout},
      {:ssl, ssl_opts()}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, [
           {:body_format, :binary}
         ]) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        parse_beacon_block(body)

      {:ok, {{_, status_code, _}, _, _body}} ->
        {:error, {:http_status, status_code}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec parse_beacon_block(binary()) ::
          {:ok, non_neg_integer(), map()} | {:error, term()}
  def parse_beacon_block(json_body) do
    case Jason.decode(json_body) do
      {:ok, %{"data" => %{"message" => %{"slot" => slot_str, "body" => body}}}} ->
        slot = parse_slot(slot_str)

        case get_execution_payload(body) do
          nil -> {:error, :no_execution_payload}
          payload -> {:ok, slot, payload}
        end

      {:ok, _} ->
        {:error, :unexpected_format}

      {:error, reason} ->
        {:error, {:json_decode, reason}}
    end
  end

  @spec parse_slot(String.t() | integer()) :: non_neg_integer()
  defp parse_slot(slot) when is_integer(slot), do: slot
  defp parse_slot(slot) when is_binary(slot), do: String.to_integer(slot)

  @doc false
  @spec get_execution_payload(map()) :: map() | nil
  def get_execution_payload(body) do
    body["execution_payload"] ||
      get_in(body, ["execution_payload_header"])
  end

  # --- Payload processing ---

  @spec process_execution_payload(map(), %__MODULE__{}) :: %__MODULE__{}
  defp process_execution_payload(payload, state) do
    block_number = parse_hex_or_int(payload["block_number"])
    block_hash = payload["block_hash"]
    parent_hash = payload["parent_hash"]

    Logger.info(
      "BeaconFetcher: processing block ##{block_number} " <>
        "hash=#{truncate_hash(block_hash)} parent=#{truncate_hash(parent_hash)}"
    )

    params = [payload, [], nil, []]

    try do
      result = EthRpc.Engine.new_payload_v4(params)

      case result do
        {:ok, %{"status" => "VALID"}} ->
          Logger.info("BeaconFetcher: block ##{block_number} -> VALID")
          update_fork_choice(block_hash)
          report_engine("newPayload", "VALID")
          %{state | last_block_number: block_number}

        {:ok, %{"status" => status}} ->
          Logger.info("BeaconFetcher: block ##{block_number} -> #{status}")
          report_engine("newPayload", status)
          %{state | last_block_number: block_number}

        {:ok, %{"payloadStatus" => %{"status" => status}}} ->
          Logger.info("BeaconFetcher: block ##{block_number} -> #{status}")
          report_engine("newPayload", status)
          %{state | last_block_number: block_number}

        other ->
          Logger.warning("BeaconFetcher: unexpected result: #{inspect(other)}")
          state
      end
    rescue
      e ->
        Logger.error("BeaconFetcher: Engine call failed: #{Exception.message(e)}")
        state
    end
  end

  @spec update_fork_choice(String.t() | nil) :: :ok
  defp update_fork_choice(nil), do: :ok

  defp update_fork_choice(block_hash) do
    zero_hash = "0x" <> String.duplicate("0", 64)

    fc_state = %{
      "headBlockHash" => block_hash,
      "safeBlockHash" => block_hash,
      "finalizedBlockHash" => zero_hash
    }

    try do
      EthRpc.Engine.forkchoice_updated_v3([fc_state, nil])
      report_engine("forkchoiceUpdated", "VALID")
      :ok
    rescue
      e ->
        Logger.warning("BeaconFetcher: FCU failed: #{Exception.message(e)}")
        :ok
    end
  end

  # --- Helpers ---

  @doc false
  @spec parse_hex_or_int(term()) :: non_neg_integer()
  def parse_hex_or_int("0x" <> hex), do: String.to_integer(hex, 16)
  def parse_hex_or_int(str) when is_binary(str), do: String.to_integer(str)
  def parse_hex_or_int(int) when is_integer(int), do: int
  def parse_hex_or_int(_), do: 0

  @spec truncate_hash(String.t() | nil) :: String.t()
  defp truncate_hash(nil), do: "nil"
  defp truncate_hash(hash) when is_binary(hash), do: String.slice(hash, 0, 18) <> "..."
  defp truncate_hash(_), do: "?"

  @spec report_engine(String.t(), String.t()) :: :ok
  defp report_engine(method, status) do
    try do
      EthDashboard.Collector.report_engine(method, status)
    catch
      _, _ -> :ok
    end
  end

  @spec ensure_http_client_started() :: :ok
  defp ensure_http_client_started do
    :inets.start()
    :ssl.start()
    :ok
  end

  @spec ssl_opts() :: keyword()
  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
