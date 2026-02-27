defmodule EthNet do
  @moduledoc """
  Ethereum DevP2P networking layer.

  Provides peer discovery (DiscV4), encrypted transport (RLPx),
  and eth/68 protocol support for connecting to Ethereum mainnet nodes.
  """

  @doc "Returns the number of connected peers."
  defdelegate connected_count, to: EthNet.Peer.Manager

  @doc "Returns info about connected peers."
  defdelegate connected_peers, to: EthNet.Peer.Manager

  @doc "Returns the node's enode URL."
  def enode_url(ip \\ "0.0.0.0", port \\ 30303) do
    EthNet.NodeKey.enode_url(ip, port)
  end
end
