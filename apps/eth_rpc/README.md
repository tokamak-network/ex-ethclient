# EthRpc

JSON-RPC 2.0 server for the ex_ethclient execution client.

Exposes the standard Ethereum JSON-RPC API via HTTP (Bandit + Plug). Supports `eth_*`, `net_*`, `web3_*`, `debug_*`, `admin_*`, `txpool_*` namespaces, and the Engine API (`engine_*`) for consensus layer communication with JWT authentication.

## Key Modules

- `EthRpc.Eth` - `eth_*` namespace (blocks, transactions, accounts, logs, filters)
- `EthRpc.Engine` - Engine API for beacon chain integration (newPayload, forkchoiceUpdated)
- `EthRpc.Debug` - `debug_*` namespace (tracing, raw blocks/receipts)
- `EthRpc.Admin` - `admin_*` namespace (node info, peers)
- `EthRpc.Txpool` - `txpool_*` namespace (mempool inspection)
- `EthRpc.FilterManager` - Log/block/pending tx filter management
- `EthRpc.Metrics` - Telemetry/Prometheus metrics and `/metrics` endpoint
- `EthRpc.JwtAuth` - JWT authentication for Engine API
- `EthRpc.Formatters` - Hex encoding for JSON-RPC responses
