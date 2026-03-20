---
name: phase-status
description: Show current implementation phase status, test counts per app, and next steps for ex_ethclient development.
user-invocable: true
allowed-tools: Bash, Glob, Grep, Read
---

# Phase Status Report

Generate a comprehensive status report of ex_ethclient development progress.

## Steps

1. Run `mix test` from the project root and capture the output to get total test counts
2. For each umbrella app (eth_core, eth_crypto, eth_net, eth_storage, eth_rpc):
   - Count test files: `apps/<app>/test/**/*_test.exs`
   - Check if the app has real implementation or is a placeholder (look for actual modules with functions beyond `@moduledoc`)
   - Determine status: PRODUCTION / IN PROGRESS / PLACEHOLDER
3. Check for compilation warnings: `mix compile --warnings-as-errors 2>&1`
4. Check Credo status: `mix credo --strict --format oneline 2>&1 | tail -5`

## Output Format

```
# ex_ethclient Phase Status Report

## Test Summary
Total: X tests, Y failures

## App Status
| App | Status | Tests | Notes |
|-----|--------|-------|-------|
| eth_core | PRODUCTION | XX | All 5 tx types, RLP, signing |
| ... | ... | ... | ... |

## Phase Roadmap
- [x] Phase 1: Core Types & Signing
- [x] Phase 3: Networking (DiscV4, RLPx, eth/68)
- [ ] Phase 2: Storage (RocksDB NIF, MPT)
- [ ] Phase 2.5: EVM (revm NIF)
- [ ] Phase 3.5: Chain (block validation, state transitions)
- [ ] Phase 4: RPC (JSON-RPC, Engine API)
- [ ] Phase 5: Sync

## Next Steps
<List the 3-5 most important next tasks>
```
