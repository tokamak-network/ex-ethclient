---
paths:
  - "apps/**/test/**/*.exs"
---

# Testing Rules

## Structure
- Use `describe/2` blocks to group by feature or function
- Test names in English sentence form: `"signs and recovers a message"`
- Use `async: true` for tests without shared state

## Test Priorities
1. Ethereum official test vectors (highest priority)
2. Round-trip tests: encode → decode, sign → recover
3. Edge cases: empty inputs, max values, boundary conditions
4. Property-based tests with StreamData for complex invariants

## Fixtures
- Store test vectors in `test/fixtures/` as JSON or binary
- Reference source (EIP number, test suite name) in comments
- Prefer hex-encoded strings for readability, decode in setup

## Assertions
- Assert specific values, not just `{:ok, _}`
- Compare binary outputs in hex for readable failure messages
- Use `assert_raise` only for truly unexpected/programmer errors

## Organization
- One test file per module: `my_module_test.exs` tests `MyModule`
- Shared test helpers in `test/support/`
- Config: `config :eth_net, start_services: false` in `test.exs`
