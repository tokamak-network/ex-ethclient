# Architecture Decisions

## ADR-001: Hybrid Elixir + Rust Architecture

- **Status**: Accepted
- **Context**: Ethereum EVM requires processing millions of gas per second. Elixir excels at concurrency but is weak at CPU-bound computation.
- **Decision**: Use Elixir OTP for networking/orchestration, Rust NIFs for EVM/hashing/storage.
- **Consequences**: Type conversion overhead at NIF boundary. Must manage BEAM scheduler blocking risk with dirty schedulers.

## ADR-002: revm for EVM Execution

- **Status**: Accepted
- **Context**: Writing an EVM from scratch is error-prone and time-consuming. revm is battle-tested and used by reth.
- **Decision**: Wrap revm as a Rust NIF via Rustler. Expose `execute_transaction/2` interface.
- **Consequences**: Tied to revm's update cycle. Must bridge revm's Rust types to Elixir terms efficiently. Benefits from revm's extensive test coverage.

## ADR-003: Behaviour-based Abstraction

- **Status**: Accepted
- **Context**: Need swappable backends for storage (RocksDB vs memory) and future components.
- **Decision**: Define Elixir behaviours (`EthStorage.Backend`, `EthEvm.Executor`) as interfaces. Implementations are injected via config.
- **Consequences**: Easy to test with mock backends. Slight indirection cost. Clear API boundaries between apps.

## ADR-004: Post-Merge Only

- **Status**: Accepted
- **Context**: Pre-merge (PoW) code is dead weight for a new client. ethrex also targets post-merge.
- **Decision**: Only support post-merge Ethereum (PoS). No mining, no PoW validation, no difficulty bomb logic.
- **Consequences**: Simpler codebase. Cannot sync historical pre-merge blocks natively (would need bridge or checkpoint sync).

## ADR-005: Umbrella App Separation Criteria

- **Status**: Accepted
- **Context**: Need clear boundaries between components to enable independent development and testing.
- **Decision**: Separate into 5 umbrella apps based on dependency direction:
  - `eth_crypto` — No internal dependencies. Pure cryptographic operations (keccak, secp256k1, ECIES).
  - `eth_core` — Depends on `eth_crypto`. Domain types (Address, Hash, Transaction, Block, Account), RLP encoding, tx signing.
  - `eth_net` — Depends on `eth_core`. Networking processes (DiscV4, RLPx, eth/68). Independent supervision tree.
  - `eth_storage` — Depends on `eth_core`. Persistence layer for core types.
  - `eth_rpc` — Depends on `eth_core`, `eth_storage`. External interface for clients.
- **Consequences**: Clear dependency graph prevents circular dependencies. Each app can be compiled and tested independently.

## Dependency Graph

```
eth_rpc → eth_storage → eth_core → eth_crypto
                ↑            ↑
           eth_net ──────────┘
```
