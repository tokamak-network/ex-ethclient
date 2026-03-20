---
name: diff-test
description: Compare ex_ethclient output with reference Ethereum implementations (geth, reth, ethrex) for the same input.
user-invocable: true
allowed-tools: Bash, Read, WebFetch, Grep, Glob
argument-hint: <test-type> [test-id]
---

# Differential Testing

Compare ex_ethclient output against reference implementations for: $ARGUMENTS

## Supported Test Types

- `rlp` — RLP encoding/decoding comparison
- `tx` — Transaction signing and serialization
- `block` — Block header hashing
- `state` — State root computation
- `receipt` — Receipt root and gas used

## Steps

1. Identify the test type and optional test ID from $ARGUMENTS

2. For the given test type, prepare test input:
   - Find existing test fixtures in the project
   - If a specific test-id is given, locate that fixture

3. Run ex_ethclient's implementation on the input:
   - Use `mix run -e "..."` or invoke the relevant module function
   - Capture the output (hex-encoded where appropriate)

4. Get reference output:
   - Check if we have cached reference outputs in `test/fixtures/reference/`
   - If not, attempt to compute using available tools or known test vectors

5. Compare outputs field by field:
   ```
   # Differential Test Report: <test-type>

   ## Input
   <description of test input>

   ## Comparison
   | Field | ex_ethclient | Reference | Match |
   |-------|-------------|-----------|-------|
   | state_root | 0xabc... | 0xabc... | OK |
   | gas_used | 21000 | 21000 | OK |

   ## Mismatches
   <detailed analysis of any differences>

   ## Root Cause Analysis
   <if mismatches found, suggest likely causes>
   ```
