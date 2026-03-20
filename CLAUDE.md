# ex_ethclient

## Overview

Elixir L1 Ethereum Execution Client for client diversity.
Hybrid architecture: Elixir OTP for networking/orchestration, Rust NIFs for performance-critical paths.
Reference: ethrex. Post-Merge only (no PoW).

## Project Structure

Umbrella project with 7 apps:

| App | Role | Language |
|-----|------|----------|
| `eth_core` | Core types (Address, Hash, Transaction, Block, Account), RLP, tx signing | Elixir |
| `eth_crypto` | Keccak-256, secp256k1, ECIES encryption | Elixir + NIF |
| `eth_net` | P2P: DiscV4 discovery, RLPx transport, eth/68 protocol | Elixir |
| `eth_storage` | Backend behaviour, in-memory (ETS) store, MPT trie | Elixir |
| `eth_vm` | EVM behaviour, types, mock executor, gas constants | Elixir |
| `eth_chain` | Block validation, gas calc, base fee, mempool, fork config | Elixir |
| `eth_rpc` | JSON-RPC 2.0 server (Bandit + Plug), eth/net/web3 namespaces | Elixir |

### Elixir vs Rust Responsibility

| Elixir (OTP) | Rust (NIF) |
|--------------|------------|
| Networking, supervision trees | EVM execution (revm) |
| Protocol message handling | MPT hash computation |
| RLP encode/decode | RocksDB storage backend |
| Transaction pool management | BLS12-381, KZG commitments |
| JSON-RPC server | Secp256k1 (via ex_secp256k1) |

## Phase Status

- Phase 1 (Core Types & Signing) - DONE - 128 tests
- Phase 3 (Networking) - DONE - 61 tests
- Phase 2 (Storage) - DONE (in-memory + MPT) - 48 tests — RocksDB NIF next
- Phase 2.5 (EVM) - DONE (behaviour + mock) - 17 tests — revm NIF next
- Phase 3.5 (Chain) - DONE (validation + mempool) - 62 tests — execution integration next
- Phase 4 (RPC) - DONE (stub handlers) - 48 tests — wire to storage/chain next
- Phase 5 (Sync) - TODO - Snap sync, full sync

## Build & Test

```bash
# All tests
mix test

# Single app
mix test apps/eth_core/test/

# Format check
mix format --check-formatted

# Lint
mix credo --strict

# Type check
mix dialyzer

# Start networking node
mix eth_net.start --port 30303 --datadir ./data
```

## Coding Conventions

- All public functions must have `@moduledoc`, `@doc`, `@spec`
- Binary type specs: `<<_::256>>` for 32-byte hash, `<<_::160>>` for address
- Error handling: `{:ok, value} | {:error, atom()}` — never raise for expected errors
- Use `with/1` for error propagation chains
- Credo strict mode: max line length 120, max complexity 12
- Compile with `--warnings-as-errors`
- Use `defguard` for reusable type guards (e.g., `is_address/1`)
- GenServer callbacks must have `@impl true`

## Architecture Decisions

- **EVM**: revm via Rust NIF, pre-loaded into BEAM
- **Storage**: RocksDB via Rust NIF + in-memory backend for tests
- **MPT**: Rust NIF for hashing, Elixir for trie structure
- **Trie**: Behaviour-based abstraction to prepare for Verkle transition
- **Networking**: Pure Elixir with OTP supervision, no Rust

## Dependencies

- **Runtime**: Elixir 1.18+ / OTP 28+ / Rust stable
- **Core**: ex_rlp ~> 0.6.0, ex_keccak ~> 0.7.8, ex_secp256k1 ~> 0.8.0
- **Net**: snappyer ~> 1.2 (Snappy compression)
- **RPC**: bandit ~> 1.6, plug ~> 1.16, jason ~> 1.4
- **Dev**: dialyxir ~> 1.4, credo ~> 1.7, ex_doc ~> 0.34

## Key Implementation Notes

- `ExSecp256k1.sign/2` returns `{:ok, {r, s, recovery_id}}`
- `ExKeccak` is one-shot only (no incremental hashing) — use cumulative buffer for MAC
- RLPx uses AES-256-CTR with 32-byte keys derived from keccak256
- EIP-8 auth/ack messages have padding after RLP data
- Test config: `config :eth_net, start_services: false` to skip supervision tree
- Test config: `config :eth_storage, start_services: false` to skip Store GenServer
- Test config: `config :eth_chain, start_services: false` to skip Mempool
- Test config: `config :eth_rpc, start_server: false` to skip Bandit server
