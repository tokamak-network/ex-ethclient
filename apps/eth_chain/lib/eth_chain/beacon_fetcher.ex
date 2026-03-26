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
  @batch_delay 500
  @default_endpoint "https://ethereum-sepolia-beacon-api.publicnode.com"
  @initial_delay 2_000
  @http_timeout 10_000
  @connect_timeout 5_000
  @batch_size 10

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
            head_slot: 0,
            blocks_stored: 0,
            syncing: false,
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
    case fetch_head_slot(state.endpoint) do
      {:ok, head_slot} ->
        state = %{state | head_slot: head_slot}

        if state.last_slot == 0 do
          # First run: start syncing from a recent slot (head - 100)
          start = max(head_slot - 100, 1)
          Logger.info("BeaconFetcher: head at slot #{head_slot}, starting sync from #{start}")
          state = %{state | last_slot: start - 1, syncing: true}
          send(self(), :sync_batch)
          {:noreply, state}
        else
          # Already syncing, just update head
          state = fetch_and_process_head(state)
          Process.send_after(self(), :fetch_head, @slot_time)
          {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning("BeaconFetcher: failed to get head slot: #{inspect(reason)}")
        Process.send_after(self(), :fetch_head, @slot_time)
        {:noreply, %{state | errors: state.errors + 1}}
    end
  end

  def handle_info(:sync_batch, state) do
    state = sync_batch(state)

    if state.last_slot < state.head_slot do
      Process.send_after(self(), :sync_batch, @batch_delay)
    else
      Logger.info("BeaconFetcher: caught up to head slot #{state.head_slot}")
      _state = %{state | syncing: false}
      Process.send_after(self(), :fetch_head, @slot_time)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      last_slot: state.last_slot,
      head_slot: state.head_slot,
      last_block_number: state.last_block_number,
      blocks_stored: state.blocks_stored,
      syncing: state.syncing,
      endpoint: state.endpoint,
      network: state.network,
      errors: state.errors,
      running: state.running
    }

    {:reply, reply, state}
  end

  # --- Fetch logic ---

  defp fetch_head_slot(endpoint) do
    url = "#{endpoint}/eth/v1/beacon/headers/head"
    headers = [{~c"Accept", ~c"application/json"}]
    http_opts = [{:timeout, @http_timeout}, {:connect_timeout, @connect_timeout}, {:ssl, ssl_opts()}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(body) do
          {:ok, %{"data" => %{"header" => %{"message" => %{"slot" => slot_str}}}}} ->
            {:ok, parse_slot(slot_str)}
          _ -> {:error, :unexpected_format}
        end
      {:ok, {{_, code, _}, _, _}} -> {:error, {:http_status, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_batch(state) do
    start_slot = state.last_slot + 1
    end_slot = min(start_slot + @batch_size - 1, state.head_slot)

    Logger.info("BeaconFetcher: syncing slots #{start_slot}..#{end_slot} (head: #{state.head_slot})")

    state =
      Enum.reduce(start_slot..end_slot, state, fn slot, acc ->
        case fetch_block_by_slot(acc.endpoint, slot) do
          {:ok, _slot, exec_payload} ->
            acc = process_execution_payload(exec_payload, acc)
            %{acc | last_slot: slot, blocks_stored: acc.blocks_stored + 1}

          {:error, :no_execution_payload} ->
            # Slot without execution payload (missed slot), skip
            %{acc | last_slot: slot}

          {:error, {:http_status, 404}} ->
            # Empty slot
            %{acc | last_slot: slot}

          {:error, reason} ->
            Logger.debug("BeaconFetcher: slot #{slot} fetch failed: #{inspect(reason)}")
            %{acc | last_slot: slot}
        end
      end)

    pct = if state.head_slot > 0, do: Float.round(state.last_slot / state.head_slot * 100, 2), else: 0.0
    Logger.info("BeaconFetcher: progress #{pct}% (slot #{state.last_slot}/#{state.head_slot}, #{state.blocks_stored} blocks)")
    state
  end

  defp fetch_block_by_slot(endpoint, slot) do
    url = "#{endpoint}/eth/v2/beacon/blocks/#{slot}"
    headers = [{~c"Accept", ~c"application/json"}]
    http_opts = [{:timeout, @http_timeout}, {:connect_timeout, @connect_timeout}, {:ssl, ssl_opts()}]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, [{:body_format, :binary}]) do
      {:ok, {{_, 200, _}, _, body}} -> parse_beacon_block(body)
      {:ok, {{_, 404, _}, _, _}} -> {:error, {:http_status, 404}}
      {:ok, {{_, code, _}, _, _}} -> {:error, {:http_status, code}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec fetch_and_process_head(%__MODULE__{}) :: %__MODULE__{}
  defp fetch_and_process_head(state) do
    case fetch_head_block(state.endpoint) do
      {:ok, slot, exec_payload} ->
        if slot > state.last_slot do
          Logger.info("BeaconFetcher: new block at slot #{slot}")
          state = process_execution_payload(exec_payload, state)
          %{state | last_slot: slot, blocks_stored: state.blocks_stored + 1, errors: 0}
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
    # Convert Beacon API snake_case keys to Engine API camelCase
    payload = to_camel_case(payload)

    block_number = parse_hex_or_int(payload["blockNumber"] || payload["block_number"])
    block_hash = payload["blockHash"] || payload["block_hash"]
    parent_hash = payload["parentHash"] || payload["parent_hash"]

    Logger.info(
      "BeaconFetcher: processing block ##{block_number} " <>
        "hash=#{truncate_hash(block_hash)} parent=#{truncate_hash(parent_hash)}"
    )

    params = [payload, [], nil, []]

    try do
      result = apply(EthRpc.Engine, :new_payload_v4, [params])
      Logger.info("BeaconFetcher: raw engine result: #{inspect(result)}")

      # Extract status from any response format
      status = extract_status(result)
      Logger.info("BeaconFetcher: block ##{block_number} -> #{status}")
      report_engine("newPayload", status)

      if status == "VALID" do
        update_fork_choice(block_hash)
        # Report block to dashboard
        report_block(block_number, block_hash, payload)
      end

      %{state | last_block_number: block_number}
    rescue
      e ->
        Logger.error("BeaconFetcher: Engine call failed: #{Exception.message(e)}")
        state
    end
  end

  defp extract_status({:ok, %{"status" => s}}), do: s
  defp extract_status({:ok, %{"payloadStatus" => %{"status" => s}}}), do: s
  defp extract_status({:ok, map}) when is_map(map) do
    # Try to find status in any nested structure
    map["status"] || get_in(map, ["payloadStatus", "status"]) || "UNKNOWN"
  end
  defp extract_status(_), do: "UNKNOWN"

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
      apply(EthRpc.Engine, :forkchoice_updated_v3, [[fc_state, nil]])
      report_engine("forkchoiceUpdated", "VALID")
      :ok
    rescue
      e ->
        Logger.warning("BeaconFetcher: FCU failed: #{Exception.message(e)}")
        :ok
    end
  end

  # Fields that Engine API expects as hex quantities (not hashes/addresses)
  @quantity_fields MapSet.new([
    "blockNumber", "gasLimit", "gasUsed", "timestamp", "baseFeePerGas",
    "blobGasUsed", "excessBlobGas"
  ])

  # Beacon API returns snake_case keys with decimal values.
  # Engine API expects camelCase keys with "0x..." hex values.
  defp to_camel_case(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      camel_key = snake_to_camel(k)
      value = if MapSet.member?(@quantity_fields, camel_key), do: to_hex(v), else: v
      {camel_key, value}
    end)
  end

  defp snake_to_camel(key) when is_binary(key) do
    case String.split(key, "_") do
      [first | rest] ->
        first <> Enum.map_join(rest, "", &String.capitalize/1)
      _ -> key
    end
  end

  defp to_hex(v) when is_integer(v), do: "0x" <> Integer.to_string(v, 16)
  defp to_hex(v) when is_binary(v) do
    if String.starts_with?(v, "0x"), do: v, else: "0x" <> Integer.to_string(String.to_integer(v), 16)
  end
  defp to_hex(v), do: v

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

  defp report_block(block_number, block_hash, payload) do
    tx_count = length(payload["transactions"] || [])
    gas_used = parse_hex_or_int(payload["gasUsed"] || "0")
    hash_bin = case block_hash do
      "0x" <> hex -> Base.decode16!(hex, case: :mixed)
      _ -> <<0::256>>
    end

    try do
      apply(EthDashboard.Collector, :report_block, [block_number, hash_bin, tx_count, gas_used])
    catch
      _, _ -> :ok
    end
  end

  @spec report_engine(String.t(), String.t()) :: :ok
  defp report_engine(method, status) do
    try do
      apply(EthDashboard.Collector, :report_engine, [method, status])
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
