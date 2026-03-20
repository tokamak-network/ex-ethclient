---
paths:
  - "apps/**/native/**/*.rs"
  - "**/Cargo.toml"
---

# Rust NIF Development Rules

## Framework
- Use Rustler with `#[rustler::nif]` macro
- Module naming: `native/<nif_name>/src/lib.rs`

## Scheduling
- Operations < 1ms: default scheduler (normal NIF)
- Operations 1ms–100ms: `schedule = "DirtyCpu"`
- I/O operations: `schedule = "DirtyIo"`
- Never block the BEAM scheduler with long-running NIFs

## Type Conversion at NIF Boundary
- `U256` ↔ 32-byte binary (`<<_::256>>`)
- `Address` ↔ 20-byte binary (`<<_::160>>`)
- `H256` ↔ 32-byte binary
- Use `Binary` and `OwnedBinary` for zero-copy where possible
- Return `Ok(tuple)` or `Err(Error::Term)` → maps to Elixir `{:ok, _} | {:error, _}`

## Error Handling
- All NIF functions return `Result<T, Error>` — never panic
- Map Rust errors to descriptive Elixir atoms (e.g., `:invalid_input`, `:storage_error`)
- Use `#[rustler::nif(schedule = "DirtyCpu")]` for fallible operations that may take time

## Memory Safety
- Avoid holding references to Erlang terms across NIF calls
- Use `ResourceArc<T>` for persistent state between calls
- Drop all locks before returning from NIF
