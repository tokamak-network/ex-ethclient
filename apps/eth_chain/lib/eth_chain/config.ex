defmodule EthChain.Config do
  @moduledoc "Runtime configuration for the execution client."

  @type t :: %__MODULE__{
          network: :mainnet | :sepolia,
          chain_id: non_neg_integer(),
          network_id: non_neg_integer(),
          datadir: String.t(),
          p2p_port: non_neg_integer(),
          rpc_port: non_neg_integer(),
          rpc_enabled: boolean(),
          max_peers: non_neg_integer(),
          evm_module: module(),
          bootnodes: [String.t()]
        }

  defstruct network: :mainnet,
            chain_id: 1,
            network_id: 1,
            datadir: "./data",
            p2p_port: 30303,
            rpc_port: 8545,
            rpc_enabled: true,
            max_peers: 25,
            evm_module: EthVm.Mock,
            bootnodes: []

  @doc """
  Loads configuration from Application env merged with the given overrides.

  Supported keys: `:network`, `:chain_id`, `:network_id`, `:datadir`, `:port` (P2P),
  `:rpc_port`, `:rpc`, `:max_peers`, `:evm_module`, `:bootnodes`.

  When `:network` is set to `:sepolia`, the chain_id, network_id, and bootnodes
  default to Sepolia values unless explicitly overridden.
  """
  @spec from_env(keyword()) :: t()
  def from_env(overrides \\ []) do
    network = get_override(overrides, :network, :mainnet)
    defaults = network_defaults(network)

    %__MODULE__{
      network: network,
      chain_id: get_override(overrides, :chain_id, defaults.chain_id),
      network_id: get_override(overrides, :network_id, defaults.network_id),
      datadir: get_override(overrides, :datadir, "./data"),
      p2p_port: get_override(overrides, :port, 30303),
      rpc_port: get_override(overrides, :rpc_port, 8545),
      rpc_enabled: get_override(overrides, :rpc, true),
      max_peers: get_override(overrides, :max_peers, 25),
      evm_module: get_override(overrides, :evm_module, EthVm.Mock),
      bootnodes: get_override(overrides, :bootnodes, defaults.bootnodes)
    }
  end

  @doc "Returns the default mainnet configuration."
  @spec mainnet() :: t()
  def mainnet, do: %__MODULE__{}

  @doc "Returns the default Sepolia testnet configuration."
  @spec sepolia() :: t()
  def sepolia do
    %__MODULE__{
      network: :sepolia,
      chain_id: 11_155_111,
      network_id: 11_155_111,
      bootnodes: EthNet.Chain.bootnodes(:sepolia)
    }
  end

  @spec get_override(keyword(), atom(), term()) :: term()
  defp get_override(overrides, key, default) do
    Keyword.get(
      overrides,
      key,
      Application.get_env(:eth_chain, key, default)
    )
  end

  @spec network_defaults(atom()) :: %{chain_id: non_neg_integer(), network_id: non_neg_integer(), bootnodes: [String.t()]}
  defp network_defaults(:sepolia) do
    %{chain_id: 11_155_111, network_id: 11_155_111, bootnodes: EthNet.Chain.bootnodes(:sepolia)}
  end

  defp network_defaults(_mainnet) do
    %{chain_id: 1, network_id: 1, bootnodes: []}
  end
end
