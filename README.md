# ex_ethclient

An Elixir L1 Ethereum execution client built for client diversity.

Hybrid architecture: Elixir OTP for networking and orchestration, Rust NIFs for performance-critical computation. Post-Merge only — no PoW legacy code.

## Why Elixir?

Ethereum's security depends on [client diversity](https://clientdiversity.org/). The execution layer is dominated by Go and Rust implementations. ex_ethclient introduces **Elixir and the BEAM VM** — a runtime built for fault-tolerant, massively concurrent distributed systems — as a new execution client foundation.

- **OTP supervision trees** give natural process isolation and self-healing for P2P connections
- **Lightweight processes** map cleanly to per-peer protocol handling
- **Hot code upgrades** enable zero-downtime node updates
- **Rust NIFs** handle the tight inner loops (EVM, MPT hashing, cryptography) without sacrificing throughput

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      eth_rpc                            │
│            JSON-RPC 2.0 + Engine API                    │
├─────────────────────────────────────────────────────────┤
│                      eth_chain                          │
│       Block validation · Gas calc · Mempool             │
├──────────────────────┬──────────────────────────────────┤
│      eth_net         │           eth_vm                 │
│  DiscV4 · RLPx ·    │     EVM execution                │
│  eth/68 protocol     │     (revm NIF)                   │
├──────────────────────┼──────────────────────────────────┤
│                   eth_storage                           │
│        In-memory (ETS) · RocksDB · MPT                  │
├──────────────────────┴──────────────────────────────────┤
│      eth_core        │        eth_crypto                │
│  Types · RLP ·       │  Keccak-256 · secp256k1 ·       │
│  Tx signing          │  ECIES encryption                │
└──────────────────────┴──────────────────────────────────┘
```

### Umbrella Apps

| App | Role | Tests |
|-----|------|-------|
| `eth_core` | Core types (Address, Hash, Transaction, Block, Account), RLP encoding, tx signing | 144 |
| `eth_crypto` | Keccak-256, secp256k1, ECIES encryption via NIFs | 25 |
| `eth_net` | P2P networking: DiscV4 discovery, RLPx transport, eth/68 protocol | 215 |
| `eth_storage` | Storage backends (ETS + RocksDB), Merkle Patricia Trie | 173 |
| `eth_vm` | EVM behaviour, types, mock executor, gas constants | 87 |
| `eth_chain` | Block validation, gas calculation, base fee, mempool, fork config | 174 |
| `eth_rpc` | JSON-RPC 2.0 server (Bandit + Plug), Engine API with JWT auth | 213 |

### Elixir vs Rust Responsibility

| Elixir (OTP) | Rust (NIF) |
|--------------|------------|
| Networking, supervision trees | EVM execution (revm) |
| Protocol message handling | MPT hash computation |
| RLP encode/decode | RocksDB storage backend |
| Transaction pool management | BLS12-381, KZG commitments |
| JSON-RPC server | secp256k1 signatures |

## Status

> **Alpha** — under active development, not yet suitable for production use.

| Phase | Status |
|-------|--------|
| Phase 1 — Core Types & Signing | Done |
| Phase 2 — Storage (in-memory + MPT) | Done |
| Phase 2.5 — EVM (behaviour + mock) | Done |
| Phase 3 — Networking (DiscV4, RLPx, eth/68) | Done |
| Phase 3.5 — Chain (validation + mempool) | Done |
| Phase 4 — RPC (JSON-RPC + Engine API) | Done |
| Phase 5 — Sync (snap sync, full sync) | In progress |
| Rust NIFs — revm, RocksDB, MPT hashing | In progress |

## Getting Started

### Prerequisites

- Elixir 1.18+ / OTP 28+
- Rust stable (for NIF compilation)

### Build

```bash
git clone https://github.com/tokamak-network/ex_ethclient.git
cd ex_ethclient
mix deps.get
mix compile
```

### Test

```bash
# Run all tests
mix test

# Single app
mix test apps/eth_core/test/

# Format check
mix format --check-formatted

# Lint
mix credo --strict

# Type check
mix dialyzer
```

### Run a Node

```bash
# Start with P2P networking
mix eth_net.start --port 30303 --datadir ./data

# Start JSON-RPC server (default: port 8545)
mix eth_rpc.start
```

## Design Philosophy

1. **Client diversity first** — a new language runtime on the execution layer reduces correlated failure risk
2. **Modularity** — umbrella apps with clear boundaries; swap backends without touching protocol logic
3. **Correctness over speed** — comprehensive test suite (1,000+ tests), type specs on all public APIs
4. **Leverage the BEAM** — use OTP patterns (GenServer, Supervisor, Registry) instead of reinventing concurrency primitives
5. **Rust where it matters** — NIFs for tight loops only; keep the majority of logic in Elixir for maintainability

## Reference

- Primary reference implementation: [ethrex](https://github.com/lambdaclass/ethrex) (Rust)
- Cross-referenced with: [geth](https://github.com/ethereum/go-ethereum), [reth](https://github.com/paradigmxyz/reth)

## Security

If you discover a security vulnerability, please report it responsibly via [GitHub Security Advisories](https://github.com/tokamak-network/ex_ethclient/security/advisories) or email the maintainers directly. Do not open a public issue.

## License

MIT
