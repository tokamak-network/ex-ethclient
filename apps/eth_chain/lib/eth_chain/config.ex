defmodule EthChain.Config do
  @moduledoc "Runtime configuration for the execution client."

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          network_id: non_neg_integer(),
          datadir: String.t(),
          p2p_port: non_neg_integer(),
          rpc_port: non_neg_integer(),
          engine_port: non_neg_integer(),
          rpc_enabled: boolean(),
          max_peers: non_neg_integer(),
          evm_module: module(),
          bootnodes: [String.t()]
        }

  defstruct chain_id: 1,
            network_id: 1,
            datadir: "./data",
            p2p_port: 30303,
            rpc_port: 8545,
            engine_port: 8551,
            rpc_enabled: true,
            max_peers: 25,
            evm_module: EthVm.Mock,
            bootnodes: []

  @doc """
  Loads configuration from Application env merged with the given overrides.

  Supported keys: `:chain_id`, `:network_id`, `:datadir`, `:port` (P2P),
  `:rpc_port`, `:rpc`, `:max_peers`, `:evm_module`, `:bootnodes`.
  """
  @spec from_env(keyword()) :: t()
  def from_env(overrides \\ []) do
    %__MODULE__{
      chain_id: get_override(overrides, :chain_id, 1),
      network_id: get_override(overrides, :network_id, 1),
      datadir: get_override(overrides, :datadir, "./data"),
      p2p_port: get_override(overrides, :port, 30303),
      rpc_port: get_override(overrides, :rpc_port, 8545),
      engine_port: get_override(overrides, :engine_port, 8551),
      rpc_enabled: get_override(overrides, :rpc, true),
      max_peers: get_override(overrides, :max_peers, 25),
      evm_module: get_override(overrides, :evm_module, EthVm.Mock),
      bootnodes: get_override(overrides, :bootnodes, [])
    }
  end

  @doc "Returns the default mainnet configuration."
  @spec mainnet() :: t()
  def mainnet, do: %__MODULE__{}

  @spec get_override(keyword(), atom(), term()) :: term()
  defp get_override(overrides, key, default) do
    Keyword.get(
      overrides,
      key,
      Application.get_env(:eth_chain, key, default)
    )
  end
end
