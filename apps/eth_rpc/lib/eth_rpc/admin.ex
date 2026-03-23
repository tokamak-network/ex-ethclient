defmodule EthRpc.Admin do
  @moduledoc """
  Implements admin_ RPC namespace methods.

  Provides administrative operations such as node info, peer management,
  and log level control.
  """

  @doc """
  Returns information about the running node.

  Returns a map with enode URI, node ID, client name, and protocol info.
  """
  @spec node_info(list()) :: {:ok, map()}
  def node_info(_params) do
    {:ok,
     %{
       "enode" => "enode://unknown@127.0.0.1:30303",
       "id" => "unknown",
       "name" => "ExEthclient/0.1.0",
       "ip" => "127.0.0.1",
       "ports" => %{
         "discovery" => 30303,
         "listener" => 30303
       },
       "listenAddr" => "0.0.0.0:30303",
       "protocols" => %{
         "eth" => %{
           "version" => 68,
           "network" => 1,
           "difficulty" => 0,
           "genesis" => "0x" <> String.duplicate("0", 64),
           "head" => "0x" <> String.duplicate("0", 64)
         }
       }
     }}
  end

  @doc """
  Returns the list of currently connected peers.

  Returns an empty list when no peers are connected.
  """
  @spec peers(list()) :: {:ok, [map()]}
  def peers(_params) do
    {:ok, []}
  end

  @doc """
  Adds a static peer by enode URI.

  ## Parameters

    - `[enode_uri]` - The enode URI of the peer to add

  ## Returns

    `{:ok, true}` if the peer was added successfully.
  """
  @spec add_peer(list()) ::
          {:ok, boolean()} | {:error, integer(), String.t()}
  def add_peer([enode_uri | _rest]) when is_binary(enode_uri) do
    # Stub: in a real implementation, this would add the peer to the
    # static peer list of the networking layer
    {:ok, true}
  end

  def add_peer(_params) do
    {:error, -32602, "Invalid params: expected [enode_uri]"}
  end

  @doc """
  Sets the Logger level at runtime.

  ## Parameters

    - `[level_string]` - One of "debug", "info", "warning", "error"

  ## Returns

    `{:ok, true}` on success, or an error for invalid levels.
  """
  @spec set_log_level(list()) ::
          {:ok, boolean()} | {:error, integer(), String.t()}
  def set_log_level([level_str | _rest]) when is_binary(level_str) do
    case parse_log_level(level_str) do
      {:ok, level} ->
        Logger.configure(level: level)
        {:ok, true}

      :error ->
        {:error, -32602, "Invalid log level: #{level_str}"}
    end
  end

  def set_log_level(_params) do
    {:error, -32602, "Invalid params: expected [level]"}
  end

  # -- Private helpers -------------------------------------------------------

  @spec parse_log_level(String.t()) :: {:ok, atom()} | :error
  defp parse_log_level("debug"), do: {:ok, :debug}
  defp parse_log_level("info"), do: {:ok, :info}
  defp parse_log_level("warning"), do: {:ok, :warning}
  defp parse_log_level("warn"), do: {:ok, :warning}
  defp parse_log_level("error"), do: {:ok, :error}
  defp parse_log_level(_), do: :error
end
