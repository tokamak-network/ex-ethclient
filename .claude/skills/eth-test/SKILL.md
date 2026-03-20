---
name: eth-test
description: Run Ethereum official test fixtures (state tests, blockchain tests, MPT tests) against ex_ethclient modules.
user-invocable: true
allowed-tools: Bash, Read, Grep, Glob
argument-hint: [state|blockchain|mpt|rlp|all]
---

# Ethereum Official Test Runner

Run and report on Ethereum official test fixtures for category: $ARGUMENTS

## Steps

1. Check if test fixtures exist in the project:
   - Look for `test/fixtures/` directories in each app
   - Look for `ethereum/tests` submodule or downloaded fixtures
   - If not found, inform the user how to obtain them:
     ```
     git clone https://github.com/ethereum/tests.git test/fixtures/ethereum-tests
     ```

2. Based on the argument ($ARGUMENTS), run the appropriate tests:
   - `state` — State transition tests (EVM execution)
   - `blockchain` — Block validation tests
   - `mpt` — Merkle Patricia Trie tests
   - `rlp` — RLP encoding/decoding tests
   - `all` — Run all available test categories

3. For each test category:
   - Find matching test files
   - Run with `mix test --trace` filtering to the relevant test tags/paths
   - Capture pass/fail counts

4. Generate a report:
   ```
   # Ethereum Test Results: <category>

   ## Summary
   Passed: X / Y total
   Failed: Z

   ## Failures by Category
   | Test | Expected | Got | Likely Cause |
   |------|----------|-----|-------------|

   ## Recommendations
   - Priority fixes based on failure patterns
   ```
