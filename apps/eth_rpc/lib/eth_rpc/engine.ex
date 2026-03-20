defmodule EthRpc.Engine do
  @moduledoc "Engine API (engine_) for consensus layer communication."

  alias EthRpc.{ForkChoice, Hex, PayloadManager, PayloadParser}
  alias EthStorage.BlockStore

  @type rpc_result ::
          {:ok, map()} | {:error, integer(), String.t()}

  @supported_methods [
    "engine_forkchoiceUpdatedV3",
    "engine_newPayloadV3",
    "engine_getPayloadV3"
  ]

  @doc """
  engine_exchangeCapabilities

  Returns the list of supported Engine API methods.
  """
  @spec exchange_capabilities(list()) :: {:ok, list()}
  def exchange_capabilities(_params) do
    {:ok, @supported_methods}
  end

  @doc """
  engine_forkchoiceUpdatedV3

  Called by the consensus layer to update fork choice and
  optionally trigger payload building.
  """
  @spec forkchoice_updated_v3(list()) :: {:ok, map()}
  def forkchoice_updated_v3(params) do
    {fc_state, payload_attrs} = parse_fcu_params(params)
    head_hash = decode_hash_field(fc_state["headBlockHash"])
    safe_hash = decode_hash_field(fc_state["safeBlockHash"])
    finalized_hash = decode_hash_field(fc_state["finalizedBlockHash"])

    case lookup_header(head_hash) do
      {:ok, _header} ->
        update_fork_choice(head_hash, safe_hash, finalized_hash)
        handle_payload_attrs(head_hash, payload_attrs, "VALID")

      {:error, :not_found} ->
        syncing_response(nil)

      {:error, _reason} ->
        syncing_response(nil)
    end
  end

  @doc """
  engine_newPayloadV3

  Called by consensus layer to validate and execute a new block.
  """
  @spec new_payload_v3(list()) :: {:ok, map()}
  def new_payload_v3(params) do
    with {:ok, payload_map} <- extract_payload(params),
         {:ok, block} <- PayloadParser.parse_execution_payload(payload_map),
         {:ok, parent} <- lookup_parent(block) do
      execute_and_store(block, parent)
    else
      {:error, :parent_not_found} ->
        {:ok, payload_status("SYNCING", nil, nil)}

      {:error, reason} ->
        {:ok, payload_status("INVALID", nil, "Validation error: #{reason}")}
    end
  end

  @doc """
  engine_getPayloadV3

  Retrieves a payload that was started via forkchoiceUpdated.
  """
  @spec get_payload_v3(list()) :: {:ok, map()} | {:error, integer(), String.t()}
  def get_payload_v3(params) do
    with {:ok, payload_id} <- parse_payload_id(params),
         {:ok, payload_data} <- fetch_payload(payload_id) do
      build_get_payload_response(payload_data)
    else
      {:error, :not_found} ->
        {:error, -38001, "Unknown payload"}

      {:error, _reason} ->
        {:error, -38001, "Unknown payload"}
    end
  end

  # --- Private helpers ---

  @spec parse_fcu_params(list()) :: {map(), map() | nil}
  defp parse_fcu_params([fc_state, payload_attrs | _]) do
    {fc_state || %{}, payload_attrs}
  end

  defp parse_fcu_params([fc_state | _]) do
    {fc_state || %{}, nil}
  end

  defp parse_fcu_params(_), do: {%{}, nil}

  @spec decode_hash_field(String.t() | nil) :: binary()
  defp decode_hash_field(nil), do: <<0::256>>

  defp decode_hash_field(hex) when is_binary(hex) do
    case Hex.decode_data(hex) do
      {:ok, <<_::256>> = hash} -> hash
      _ -> <<0::256>>
    end
  end

  @spec lookup_header(<<_::256>>) ::
          {:ok, term()} | {:error, :not_found | term()}
  defp lookup_header(hash) do
    store = store_server()

    case BlockStore.get_header(hash, store) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, header} -> {:ok, header}
      {:error, _} = err -> err
    end
  catch
    :exit, _ -> {:error, :store_unavailable}
  end

  @spec update_fork_choice(binary(), binary(), binary()) :: :ok
  defp update_fork_choice(head, safe, finalized) do
    if GenServer.whereis(ForkChoice) do
      ForkChoice.update(head, safe, finalized)
    else
      :ok
    end
  end

  @spec handle_payload_attrs(binary(), map() | nil, String.t()) ::
          {:ok, map()}
  defp handle_payload_attrs(head_hash, nil, status) do
    {:ok,
     %{
       "payloadStatus" => payload_status(status, head_hash, nil),
       "payloadId" => nil
     }}
  end

  defp handle_payload_attrs(head_hash, attrs, status) when is_map(attrs) do
    payload_id = create_payload(attrs)

    {:ok,
     %{
       "payloadStatus" => payload_status(status, head_hash, nil),
       "payloadId" => Hex.encode_quantity(payload_id)
     }}
  end

  @spec create_payload(map()) :: non_neg_integer()
  defp create_payload(attrs) do
    if GenServer.whereis(PayloadManager) do
      {:ok, id} = PayloadManager.new_payload(attrs)
      id
    else
      0
    end
  end

  @spec syncing_response(binary() | nil) :: {:ok, map()}
  defp syncing_response(payload_id) do
    {:ok,
     %{
       "payloadStatus" => payload_status("SYNCING", nil, nil),
       "payloadId" => payload_id
     }}
  end

  @spec payload_status(String.t(), binary() | nil, String.t() | nil) ::
          map()
  defp payload_status(status, latest_valid_hash, validation_error) do
    %{
      "status" => status,
      "latestValidHash" => encode_optional_hash(latest_valid_hash),
      "validationError" => validation_error
    }
  end

  @spec encode_optional_hash(binary() | nil) :: String.t() | nil
  defp encode_optional_hash(nil), do: nil
  defp encode_optional_hash(hash), do: Hex.encode_data(hash)

  @spec extract_payload(list()) :: {:ok, map()} | {:error, term()}
  defp extract_payload([payload | _]) when is_map(payload) do
    {:ok, payload}
  end

  defp extract_payload(_), do: {:error, :invalid_params}

  @spec lookup_parent(EthCore.Types.Block.t()) ::
          {:ok, term()} | {:error, :parent_not_found | term()}
  defp lookup_parent(block) do
    parent_hash = block.header.parent_hash
    store = store_server()

    case BlockStore.get_header(parent_hash, store) do
      {:ok, nil} -> {:error, :parent_not_found}
      {:ok, header} -> {:ok, header}
      {:error, _} -> {:error, :parent_not_found}
    end
  catch
    :exit, _ -> {:error, :parent_not_found}
  end

  @spec execute_and_store(
          EthCore.Types.Block.t(),
          EthCore.Types.BlockHeader.t()
        ) :: {:ok, map()}
  defp execute_and_store(block, _parent) do
    store = store_server()

    case BlockStore.store_block(block, store) do
      {:ok, block_hash} ->
        EthStorage.Store.set_latest_block_number(
          store,
          block.header.number
        )

        {:ok, payload_status("VALID", block_hash, nil)}

      {:error, reason} ->
        {:ok, payload_status("INVALID", nil, "Store error: #{reason}")}
    end
  catch
    :exit, _ ->
      {:ok, payload_status("INVALID", nil, "Store unavailable")}
  end

  @spec parse_payload_id(list()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp parse_payload_id([id | _]) when is_binary(id) do
    Hex.decode_quantity(id)
  end

  defp parse_payload_id([id | _]) when is_integer(id) do
    {:ok, id}
  end

  defp parse_payload_id(_), do: {:error, :invalid_params}

  @spec fetch_payload(non_neg_integer()) ::
          {:ok, map()} | {:error, :not_found}
  defp fetch_payload(id) do
    if GenServer.whereis(PayloadManager) do
      PayloadManager.get_payload(id)
    else
      {:error, :not_found}
    end
  end

  @spec build_get_payload_response(map()) :: {:ok, map()}
  defp build_get_payload_response(payload_data) do
    payload_map = build_execution_payload(payload_data)

    {:ok,
     %{
       "executionPayload" => payload_map,
       "blockValue" => "0x0",
       "blobsBundle" => %{
         "commitments" => [],
         "proofs" => [],
         "blobs" => []
       },
       "shouldOverrideBuilder" => false
     }}
  end

  @spec build_execution_payload(map()) :: map()
  defp build_execution_payload(%{params: params}) do
    params
  end

  @spec store_server() :: GenServer.server()
  defp store_server do
    case Application.get_env(:eth_rpc, :store) do
      nil -> EthStorage.Store
      {_mod, name} -> name
      name -> name
    end
  end
end
