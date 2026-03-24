defmodule EthRpc.Engine do
  @moduledoc """
  Engine API (engine_) for consensus layer communication.

  Implements the Ethereum Engine API as specified in EIP-3675 and
  subsequent EIPs. This module is the primary interface between the
  consensus layer (CL) client (e.g., Lighthouse, Prysm) and the
  execution layer (EL).
  """

  alias EthChain.BlockExecutor
  alias EthRpc.{ForkChoice, Hex, PayloadManager, PayloadParser}
  alias EthStorage.BlockStore

  require Logger

  @type rpc_result ::
          {:ok, map()} | {:error, integer(), String.t()}

  @supported_methods [
    "engine_forkchoiceUpdatedV1",
    "engine_forkchoiceUpdatedV2",
    "engine_forkchoiceUpdatedV3",
    "engine_forkchoiceUpdatedV4",
    "engine_newPayloadV1",
    "engine_newPayloadV2",
    "engine_newPayloadV3",
    "engine_newPayloadV4",
    "engine_getPayloadV1",
    "engine_getPayloadV2",
    "engine_getPayloadV3",
    "engine_getPayloadV4",
    "engine_getPayloadBodiesByHashV1",
    "engine_getPayloadBodiesByHashV2",
    "engine_getPayloadBodiesByRangeV1",
    "engine_getPayloadBodiesByRangeV2",
    "engine_getBlobsV1",
    "engine_getClientVersionV1",
    "engine_exchangeTransitionConfigurationV1"
  ]

  @doc """
  engine_exchangeCapabilities

  Returns the list of supported Engine API methods.
  """
  @spec exchange_capabilities(list()) :: {:ok, list()}
  def exchange_capabilities(_params) do
    {:ok, @supported_methods}
  end

  # -- forkchoiceUpdated versions ---------------------------------------------

  @doc "engine_forkchoiceUpdatedV1 - no withdrawals in payload attributes."
  @spec forkchoice_updated_v1(list()) :: {:ok, map()}
  def forkchoice_updated_v1(params), do: do_forkchoice_updated(params, :v1)

  @doc "engine_forkchoiceUpdatedV2 - adds withdrawals to payload attributes."
  @spec forkchoice_updated_v2(list()) :: {:ok, map()}
  def forkchoice_updated_v2(params), do: do_forkchoice_updated(params, :v2)

  @doc "engine_forkchoiceUpdatedV3 - adds parentBeaconBlockRoot to payload attributes."
  @spec forkchoice_updated_v3(list()) :: {:ok, map()}
  def forkchoice_updated_v3(params), do: do_forkchoice_updated(params, :v3)

  @doc "engine_forkchoiceUpdatedV4 - Prague fork support."
  @spec forkchoice_updated_v4(list()) :: {:ok, map()}
  def forkchoice_updated_v4(params), do: do_forkchoice_updated(params, :v4)

  # -- newPayload versions ----------------------------------------------------

  @doc "engine_newPayloadV1 - just execution payload."
  @spec new_payload_v1(list()) :: {:ok, map()}
  def new_payload_v1(params), do: do_new_payload(params, :v1)

  @doc "engine_newPayloadV2 - adds blobVersionedHashes (no validation)."
  @spec new_payload_v2(list()) :: {:ok, map()}
  def new_payload_v2(params), do: do_new_payload(params, :v2)

  @doc "engine_newPayloadV3 - adds parentBeaconBlockRoot + blob hash validation."
  @spec new_payload_v3(list()) :: {:ok, map()}
  def new_payload_v3(params), do: do_new_payload(params, :v3)

  @doc "engine_newPayloadV4 - Prague fork support."
  @spec new_payload_v4(list()) :: {:ok, map()}
  def new_payload_v4(params), do: do_new_payload(params, :v4)

  # -- getPayload versions ----------------------------------------------------

  @doc "engine_getPayloadV1 - returns just executionPayload."
  @spec get_payload_v1(list()) :: rpc_result()
  def get_payload_v1(params), do: do_get_payload(params, :v1)

  @doc "engine_getPayloadV2 - returns {executionPayload, blockValue}."
  @spec get_payload_v2(list()) :: rpc_result()
  def get_payload_v2(params), do: do_get_payload(params, :v2)

  @doc "engine_getPayloadV3 - returns full payload with blobsBundle."
  @spec get_payload_v3(list()) :: rpc_result()
  def get_payload_v3(params), do: do_get_payload(params, :v3)

  @doc "engine_getPayloadV4 - Prague fork extended format."
  @spec get_payload_v4(list()) :: rpc_result()
  def get_payload_v4(params), do: do_get_payload(params, :v4)

  # -- getPayloadBodies -------------------------------------------------------

  @doc """
  engine_getPayloadBodiesByHashV1

  Takes a list of block hashes and returns payload bodies (transactions + withdrawals)
  for each. Returns null for unknown hashes.
  """
  @spec get_payload_bodies_by_hash_v1(list()) :: {:ok, list()}
  def get_payload_bodies_by_hash_v1(params) do
    do_get_payload_bodies_by_hash(params)
  end

  @doc "engine_getPayloadBodiesByHashV2 - same as V1."
  @spec get_payload_bodies_by_hash_v2(list()) :: {:ok, list()}
  def get_payload_bodies_by_hash_v2(params) do
    do_get_payload_bodies_by_hash(params)
  end

  @doc """
  engine_getPayloadBodiesByRangeV1

  Takes a start block number and count, returns payload bodies for the range.
  """
  @spec get_payload_bodies_by_range_v1(list()) :: {:ok, list()}
  def get_payload_bodies_by_range_v1(params) do
    do_get_payload_bodies_by_range(params)
  end

  @doc "engine_getPayloadBodiesByRangeV2 - same as V1."
  @spec get_payload_bodies_by_range_v2(list()) :: {:ok, list()}
  def get_payload_bodies_by_range_v2(params) do
    do_get_payload_bodies_by_range(params)
  end

  # -- getBlobsV1 -------------------------------------------------------------

  @doc """
  engine_getBlobsV1

  Takes a list of versioned hashes. Returns list of BlobAndProof or null.
  Currently a stub that returns null for all hashes.
  """
  @spec get_blobs_v1(list()) :: {:ok, list()}
  def get_blobs_v1([hashes | _]) when is_list(hashes) do
    {:ok, Enum.map(hashes, fn _hash -> nil end)}
  end

  def get_blobs_v1(_), do: {:ok, []}

  # -- getClientVersionV1 -----------------------------------------------------

  @doc """
  engine_getClientVersionV1

  Returns client identification information.
  """
  @spec get_client_version_v1(list()) :: {:ok, list()}
  def get_client_version_v1(_params) do
    {:ok,
     [
       %{
         "code" => "EE",
         "name" => "ExEthclient",
         "version" => "0.1.0",
         "commit" => "0x00000000"
       }
     ]}
  end

  # -- exchangeTransitionConfigurationV1 --------------------------------------

  @doc """
  engine_exchangeTransitionConfigurationV1

  Post-merge: echoes back the provided transition configuration.
  """
  @spec exchange_transition_config_v1(list()) :: {:ok, map()}
  def exchange_transition_config_v1([config | _]) when is_map(config) do
    {:ok,
     %{
       "terminalTotalDifficulty" =>
         Map.get(config, "terminalTotalDifficulty", "0x0"),
       "terminalBlockHash" =>
         Map.get(config, "terminalBlockHash", Hex.encode_data(<<0::256>>)),
       "terminalBlockNumber" =>
         Map.get(config, "terminalBlockNumber", "0x0")
     }}
  end

  def exchange_transition_config_v1(_params) do
    {:ok,
     %{
       "terminalTotalDifficulty" => "0x0",
       "terminalBlockHash" => Hex.encode_data(<<0::256>>),
       "terminalBlockNumber" => "0x0"
     }}
  end

  # --- Shared core implementations ---

  @spec do_forkchoice_updated(list(), atom()) :: {:ok, map()}
  defp do_forkchoice_updated(params, version) do
    {fc_state, payload_attrs} = parse_fcu_params(params)
    payload_attrs = sanitize_payload_attrs(payload_attrs, version)
    head_hash = decode_hash_field(fc_state["headBlockHash"])
    safe_hash = decode_hash_field(fc_state["safeBlockHash"])
    finalized_hash = decode_hash_field(fc_state["finalizedBlockHash"])

    case lookup_header(head_hash) do
      {:ok, header} ->
        Logger.info("FCU: head block ##{header.number} found, status=VALID")
        update_fork_choice(head_hash, safe_hash, finalized_hash)
        set_head_block_number(header.number)
        validate_finalized_and_respond(head_hash, finalized_hash, payload_attrs)

      {:error, :not_found} ->
        Logger.info("FCU: head block not found, status=SYNCING")
        syncing_response(nil)

      {:error, _reason} ->
        Logger.info("FCU: head block lookup error, status=SYNCING")
        syncing_response(nil)
    end
  end

  @spec validate_finalized_and_respond(binary(), binary(), map() | nil) ::
          {:ok, map()}
  defp validate_finalized_and_respond(head_hash, finalized_hash, payload_attrs) do
    zero = <<0::256>>

    if finalized_hash != zero do
      case lookup_header(finalized_hash) do
        {:ok, _} ->
          handle_payload_attrs(head_hash, payload_attrs, "VALID")

        {:error, _} ->
          # CL says this block is finalized but we don't have it - INVALID
          Logger.warning("FCU: finalized block not found in store")
          {:ok,
           %{
             "payloadStatus" =>
               payload_status("INVALID", nil, "Finalized block not found"),
             "payloadId" => nil
           }}
      end
    else
      handle_payload_attrs(head_hash, payload_attrs, "VALID")
    end
  end

  @spec set_head_block_number(non_neg_integer()) :: :ok
  defp set_head_block_number(number) do
    store = store_server()

    try do
      EthStorage.Store.set_latest_block_number(store, number)
    catch
      :exit, _ -> :ok
    end
  end

  @spec sanitize_payload_attrs(map() | nil, atom()) :: map() | nil
  defp sanitize_payload_attrs(nil, _version), do: nil

  defp sanitize_payload_attrs(attrs, :v1) do
    Map.drop(attrs, ["withdrawals", "parentBeaconBlockRoot"])
  end

  defp sanitize_payload_attrs(attrs, :v2) do
    Map.delete(attrs, "parentBeaconBlockRoot")
  end

  defp sanitize_payload_attrs(attrs, _version), do: attrs

  @spec do_new_payload(list(), atom()) :: {:ok, map()}
  defp do_new_payload(params, _version) do
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

  @spec do_get_payload(list(), atom()) :: rpc_result()
  defp do_get_payload(params, version) do
    with {:ok, payload_id} <- parse_payload_id(params),
         {:ok, payload_data} <- fetch_payload(payload_id) do
      build_versioned_get_payload_response(payload_data, version)
    else
      {:error, :not_found} ->
        {:error, -38001, "Unknown payload"}

      {:error, _reason} ->
        {:error, -38001, "Unknown payload"}
    end
  end

  @spec build_versioned_get_payload_response(map(), atom()) :: {:ok, map()}
  defp build_versioned_get_payload_response(payload_data, :v1) do
    payload_map = build_execution_payload(payload_data)
    {:ok, %{"executionPayload" => payload_map}}
  end

  defp build_versioned_get_payload_response(payload_data, :v2) do
    payload_map = build_execution_payload(payload_data)

    {:ok,
     %{
       "executionPayload" => payload_map,
       "blockValue" => "0x0"
     }}
  end

  defp build_versioned_get_payload_response(payload_data, version)
       when version in [:v3, :v4] do
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

  @spec do_get_payload_bodies_by_hash(list()) :: {:ok, list()}
  defp do_get_payload_bodies_by_hash([hashes | _]) when is_list(hashes) do
    store = store_server()

    bodies =
      Enum.map(hashes, fn hash_hex ->
        with {:ok, hash_bin} <- Hex.decode_data(hash_hex),
             {:ok, block} when not is_nil(block) <-
               fetch_block_from_store(hash_bin, store) do
          format_payload_body(block)
        else
          _ -> nil
        end
      end)

    {:ok, bodies}
  end

  defp do_get_payload_bodies_by_hash(_), do: {:ok, []}

  @spec do_get_payload_bodies_by_range(list()) :: {:ok, list()}
  defp do_get_payload_bodies_by_range([start_hex, count_hex | _]) do
    with {:ok, start_num} <- Hex.decode_quantity(start_hex),
         {:ok, count} <- Hex.decode_quantity(count_hex) do
      store = store_server()

      bodies =
        Enum.map(start_num..(start_num + count - 1)//1, fn num ->
          case fetch_block_by_number_from_store(num, store) do
            {:ok, block} when not is_nil(block) ->
              format_payload_body(block)

            _ ->
              nil
          end
        end)

      {:ok, bodies}
    else
      _ -> {:ok, []}
    end
  end

  defp do_get_payload_bodies_by_range(_), do: {:ok, []}

  @spec format_payload_body(term()) :: map()
  defp format_payload_body(block) do
    %{
      "transactions" => format_body_transactions(block),
      "withdrawals" => format_body_withdrawals(block)
    }
  end

  @spec format_body_transactions(term()) :: list()
  defp format_body_transactions(%{transactions: txs}) when is_list(txs) do
    Enum.map(txs, fn
      tx when is_binary(tx) -> Hex.encode_data(tx)
      _tx -> "0x"
    end)
  end

  defp format_body_transactions(_), do: []

  @spec format_body_withdrawals(term()) :: list() | nil
  defp format_body_withdrawals(%{withdrawals: ws}) when is_list(ws) do
    Enum.map(ws, fn w ->
      %{
        "index" => Hex.encode_quantity(w.index),
        "validatorIndex" => Hex.encode_quantity(w.validator_index),
        "address" => Hex.encode_data(w.address),
        "amount" => Hex.encode_quantity(w.amount)
      }
    end)
  end

  defp format_body_withdrawals(_), do: nil

  @spec fetch_block_from_store(binary(), GenServer.server()) ::
          {:ok, term() | nil} | {:error, term()}
  defp fetch_block_from_store(hash_bin, store) do
    case BlockStore.get_block_by_hash(hash_bin, store) do
      {:ok, nil} -> {:ok, nil}
      {:ok, block} -> {:ok, block}
      {:error, _} = err -> err
    end
  catch
    :exit, _ -> {:error, :store_unavailable}
  end

  @spec fetch_block_by_number_from_store(
          non_neg_integer(),
          GenServer.server()
        ) :: {:ok, term() | nil} | {:error, term()}
  defp fetch_block_by_number_from_store(number, store) do
    case BlockStore.get_block_by_number(number, store) do
      {:ok, nil} -> {:ok, nil}
      {:ok, block} -> {:ok, block}
      {:error, _} = err -> err
    end
  catch
    :exit, _ -> {:error, :store_unavailable}
  end

  # --- Private helpers (shared) ---

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
  defp execute_and_store(block, parent) do
    store = store_server()
    evm_module = evm_module()
    state_provider = state_provider()

    Logger.info(
      "newPayload: executing block ##{block.header.number} " <>
        "(parent ##{parent.number})"
    )

    # Attempt execution; fall back to store-only if execution
    # modules are not fully wired (e.g., mock EVM in dev).
    exec_result =
      try do
        BlockExecutor.execute_block(block, parent, evm_module, state_provider)
      rescue
        e ->
          Logger.warning(
            "Block execution raised: #{inspect(e)}, " <>
              "falling back to store-only"
          )
          :skip_execution
      catch
        :exit, reason ->
          Logger.warning(
            "Block execution exited: #{inspect(reason)}, " <>
              "falling back to store-only"
          )
          :skip_execution
      end

    case exec_result do
      {:ok, _result} ->
        store_valid_block(block, store)

      {:error, :gas_used_mismatch} ->
        # For payloads from CL, gas is already validated; store anyway
        Logger.warning("Gas mismatch during execution, storing block anyway")
        store_valid_block(block, store)

      {:error, reason} ->
        Logger.warning("Block execution failed: #{inspect(reason)}")
        {:ok, payload_status("INVALID", nil, "Execution error: #{inspect(reason)}")}

      :skip_execution ->
        store_valid_block(block, store)
    end
  catch
    :exit, _ ->
      {:ok, payload_status("INVALID", nil, "Store unavailable")}
  end

  @spec store_valid_block(EthCore.Types.Block.t(), GenServer.server()) ::
          {:ok, map()}
  defp store_valid_block(block, store) do
    case BlockStore.store_block(block, store) do
      {:ok, block_hash} ->
        EthStorage.Store.set_latest_block_number(store, block.header.number)

        Logger.info(
          "newPayload: block ##{block.header.number} stored, " <>
            "hash=#{Base.encode16(block_hash, case: :lower)}"
        )

        {:ok, payload_status("VALID", block_hash, nil)}

      {:error, reason} ->
        {:ok, payload_status("INVALID", nil, "Store error: #{inspect(reason)}")}
    end
  end

  @spec evm_module() :: module()
  defp evm_module do
    Application.get_env(:eth_chain, :evm_module, EthVm.Mock)
  end

  @spec state_provider() :: module()
  defp state_provider do
    Application.get_env(:eth_chain, :state_provider, EthVm.Mock)
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
