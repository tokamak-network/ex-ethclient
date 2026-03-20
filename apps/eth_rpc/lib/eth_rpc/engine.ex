defmodule EthRpc.Engine do
  @moduledoc """
  Engine API namespace (engine_) for consensus layer communication.

  Provides stub implementations that return SYNCING status,
  indicating the execution client is not yet ready.
  """

  @type rpc_result ::
          {:ok, map()} | {:error, integer(), String.t()}

  @doc """
  Handle engine_forkchoiceUpdatedV3.

  Returns a SYNCING status indicating the client is still syncing.
  """
  @spec forkchoice_updated_v3(list()) :: {:ok, map()}
  def forkchoice_updated_v3(_params) do
    {:ok,
     %{
       "payloadStatus" => %{
         "status" => "SYNCING",
         "latestValidHash" => nil,
         "validationError" => nil
       },
       "payloadId" => nil
     }}
  end

  @doc """
  Handle engine_newPayloadV3.

  Returns a SYNCING status indicating the client is still syncing.
  """
  @spec new_payload_v3(list()) :: {:ok, map()}
  def new_payload_v3(_params) do
    {:ok,
     %{
       "status" => "SYNCING",
       "latestValidHash" => nil,
       "validationError" => nil
     }}
  end

  @doc """
  Handle engine_getPayloadV3.

  Returns an error since no payload is available.
  """
  @spec get_payload_v3(list()) :: {:error, integer(), String.t()}
  def get_payload_v3(_params) do
    {:error, -38001, "Unknown payload"}
  end
end
