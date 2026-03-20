defmodule EthChain.Health do
  @moduledoc "Health check for the execution client."

  @doc """
  Returns health status of all components.

  The returned map includes:
  - `:store` — `:up` or `:down`
  - `:mempool` — `:up` or `:down`
  - `:syncing` — always `false` (placeholder)
  - `:chain_head` — latest block number or `nil`
  - `:peer_count` — connected peer count (currently `0`)
  - `:uptime_seconds` — BEAM wall-clock uptime in seconds
  """
  @spec check() :: map()
  def check do
    %{
      store: check_process(EthStorage.Store),
      mempool: check_process(EthChain.Mempool),
      syncing: false,
      chain_head: get_chain_head(),
      peer_count: get_peer_count(),
      uptime_seconds: get_uptime()
    }
  end

  @spec check_process(atom()) :: :up | :down
  defp check_process(name) do
    case Process.whereis(name) do
      nil -> :down
      pid when is_pid(pid) -> :up
    end
  end

  @spec get_chain_head() :: non_neg_integer() | nil
  defp get_chain_head do
    case EthStorage.Store.get_latest_block_number() do
      {:ok, n} -> n
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  @spec get_peer_count() :: non_neg_integer()
  defp get_peer_count do
    0
  end

  @spec get_uptime() :: non_neg_integer()
  defp get_uptime do
    {uptime, _} = :erlang.statistics(:wall_clock)
    div(uptime, 1000)
  end
end
