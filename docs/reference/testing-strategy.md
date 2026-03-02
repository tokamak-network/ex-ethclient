# Testing Strategy

## Test Pyramid

```
Layer 5: Shadow Fork          — Mainnet real data verification
Layer 4: Hive                 — Docker-based client compatibility (ethereum/hive)
Layer 3: Differential         — Same input → compare output with geth/reth
Layer 2: Spec Tests           — Tens of thousands of JSON fixtures (ethereum/execution-spec-tests)
Layer 1: Unit + Property      — Per-module unit tests (ExUnit, StreamData)
```

## Current Test Counts

| App | Tests | Coverage Target |
|-----|-------|----------------|
| eth_crypto | — | 95%+ (security critical) |
| eth_core | 130 | 90%+ (protocol critical) |
| eth_net | 78 | 80%+ (networking) |
| eth_storage | — | 80%+ (after implementation) |
| eth_rpc | — | 80%+ (after implementation) |

## JSON Fixture Formats

### State Test
```json
{
  "test_name": {
    "env": {
      "currentCoinbase": "0x...",
      "currentDifficulty": "0x...",
      "currentGasLimit": "0x...",
      "currentNumber": "0x...",
      "currentTimestamp": "0x..."
    },
    "pre": {
      "0xaddr": {
        "balance": "0x...",
        "nonce": "0x...",
        "code": "0x...",
        "storage": {}
      }
    },
    "transaction": {
      "nonce": "0x...",
      "gasPrice": "0x...",
      "gasLimit": ["0x..."],
      "to": "0x...",
      "value": ["0x..."],
      "data": ["0x..."]
    },
    "post": {
      "Shanghai": [{
        "hash": "0x...",
        "indexes": { "data": 0, "gas": 0, "value": 0 }
      }]
    }
  }
}
```

### Blockchain Test
```json
{
  "test_name": {
    "genesisBlockHeader": {
      "parentHash": "0x...",
      "stateRoot": "0x...",
      "number": "0x00"
    },
    "pre": {
      "0xaddr": { "balance": "0x...", "nonce": "0x...", "code": "0x...", "storage": {} }
    },
    "blocks": [{
      "rlp": "0x...",
      "blockHeader": { "number": "0x01", "stateRoot": "0x..." },
      "transactions": [{ "nonce": "0x...", "gasPrice": "0x..." }]
    }],
    "postState": {
      "0xaddr": { "balance": "0x...", "nonce": "0x...", "code": "0x...", "storage": {} }
    }
  }
}
```

## Test Repositories

### ethereum/tests (Legacy)
- URL: https://github.com/ethereum/tests
- Some fixtures not yet migrated to new framework
- Still useful for older fork tests

### ethereum/execution-spec-tests (Current)
- URL: https://github.com/ethereum/execution-spec-tests
- Python-based test framework
- Fork-structured: `tests/shanghai/`, `tests/cancun/`, ...
- Generate fixtures: `uv run fill --fork Shanghai -m state_test`
- Pre-built releases available as JSON artifacts

## Running Tests

```bash
# All tests
mix test

# Specific app
mix test --only eth_core

# With coverage
mix test --cover

# Specific tag
mix test --only rlpx
mix test --only discv4
```

## Writing New Tests

1. Place test files in `apps/<app>/test/` mirroring `lib/` structure
2. Use `describe` blocks to group related scenarios
3. Tag integration tests with `@tag :integration`
4. Tag slow tests with `@tag :slow`
5. For fixtures, place JSON files in `apps/<app>/test/fixtures/`
