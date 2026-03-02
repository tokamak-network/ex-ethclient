# ex_ethclient

Elixir port of [ethrex](https://github.com/lambdaclass/ethrex) — Ethereum L1/L2 execution client.
Hybrid architecture: Elixir OTP for networking/orchestration, Rust NIFs for performance-critical crypto/EVM.

## Project Structure

Umbrella project with 5 apps:

| App | Role | Status |
|-----|------|--------|
| `eth_core` | Core types (Address, Hash, Transaction, Block, Account), RLP encoding, tx signing | Production |
| `eth_crypto` | Keccak-256, secp256k1, ECIES encryption | Production |
| `eth_net` | P2P networking: DiscV4 discovery, RLPx transport, eth/68 protocol | Production |
| `eth_storage` | RocksDB storage | Placeholder |
| `eth_rpc` | JSON-RPC server | Placeholder |

## Phase Status

- **Phase 1** ✅ Core Types & Signing — All 5 tx types, EIP-2, encode/decode (130 tests)
- **Phase 3** ✅ Networking — DiscV4, RLPx, eth/68, CLI (208 total tests)
- **Phase 2** 🔜 Storage & EVM — Rust NIF core (EVM/revm, MPT, BLS12-381, KZG)
- **Phase 4** 📋 Client Integration — JSON-RPC, Engine API, Mempool
- **Phase 5** 📋 Sync & Stabilization

## Key Implementation Notes

- `ExSecp256k1.sign/2` returns `{:ok, {r, s, recovery_id}}`
- `ExSecp256k1.public_key_tweak_mult/2` for ECDH (pubkey × scalar)
- ExKeccak only has one-shot API, no incremental — Mac uses cumulative buffer
- RLPx frame codec uses AES-256-CTR (keccak256 derives 32-byte keys)
- EIP-8 auth/ack messages have padding after RLP — need `split_rlp` helper
- `config :eth_net, start_services: false` in test.exs to skip supervision tree

## Environment

- Elixir 1.18.4 / OTP 28
- Rust 1.93.1 (installed via rustup)
- Dependencies: `ex_rlp`, `ex_keccak`, `ex_secp256k1`, `snappyer`, `dialyxir`, `credo`

---

## Workflow Guidelines

### Implementing a New Feature
1. Research: `/eip <number>` or delegate to `ethereum-researcher` agent
2. Check reference: Read `docs/reference/ethereum-specs.md` for related specs
3. Implement following coding conventions and architecture rules
4. Verify: `/health` to check build status
5. Self-review: delegate to `self-reviewer` agent before commit

### Adding a Rust NIF
1. Scaffold: `/nif-scaffold <app> <name>`
2. Read `docs/reference/nif-patterns.md` for implementation patterns
3. Delegate complex implementation to `nif-developer` agent
4. Security check: delegate to `security-auditor` agent

### Analyzing Test Failures
1. Delegate to `test-analyzer` agent for failure pattern classification
2. Compare with reference: `/diff-test <type>`
3. Read `docs/reference/testing-strategy.md` for fixture formats

### Routine Health Check
1. `/health` — compile + test + credo + format
2. `/phase-status` — progress overview

---

## Available Tools

### Skills
| Command | When to Use |
|---------|-------------|
| `/eip <n>` | Before implementing any EIP-related feature |
| `/phase-status` | Checking project progress |
| `/eth-test <category>` | Running Ethereum official test fixtures |
| `/nif-scaffold <app> <name>` | Starting a new Rust NIF module |
| `/diff-test <type>` | Debugging output mismatches with geth/reth |
| `/health` | Session start, before commits |

### Agents
| Agent | When to Delegate |
|-------|-----------------|
| `ethereum-researcher` | Deep protocol research, EIP analysis, reference client study |
| `nif-developer` | Rust NIF implementation, Rustler patterns, debugging |
| `test-analyzer` | Classifying test failure patterns, suggesting fixes |
| `self-reviewer` | Code review before commit (security + conventions) |
| `security-auditor` | Full module/app security audit |

---

## Reference Materials

Detailed reference documents are in `docs/reference/`. Read them when working on related areas:

| Document | Read When |
|----------|-----------|
| `docs/reference/architecture.md` | Making structural decisions, adding new modules |
| `docs/reference/ethereum-specs.md` | Implementing protocol features, EIP-related work |
| `docs/reference/testing-strategy.md` | Writing tests, analyzing failures, adding test fixtures |
| `docs/reference/phase-roadmap.md` | Planning next steps, checking completion criteria |
| `docs/reference/nif-patterns.md` | Writing or reviewing Rust NIF code |
