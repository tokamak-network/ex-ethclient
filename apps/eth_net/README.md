# EthNet

P2P networking stack for the ex_ethclient execution client.

Implements Ethereum's devp2p protocol suite: DiscV4/DiscV5 node discovery, DNS-based peer discovery (EIP-1459), RLPx encrypted transport, and eth/68 wire protocol. Built entirely in Elixir with OTP supervision.

## Key Modules

- `EthNet.DiscV4` - UDP-based node discovery (ping/pong, find/neighbours)
- `EthNet.DiscV5` - ENR-based discovery with session management
- `EthNet.DNS` - EIP-1459 DNS-based peer discovery with tree verification
- `EthNet.RLPx` - Encrypted transport (ECIES handshake, AES-256-CTR framing)
- `EthNet.Protocol.P2P` - Base p2p protocol (hello, disconnect, ping/pong)
- `EthNet.Protocol.Eth68` - eth/68 wire protocol messages
- `EthNet.Protocol.Snap1` - Snap sync protocol
- `EthNet.Peer.Manager` - Peer lifecycle and connection management
- `EthNet.Sync.Manager` - Block synchronization orchestration
- `EthNet.ForkID` - EIP-2124 fork identifier computation
