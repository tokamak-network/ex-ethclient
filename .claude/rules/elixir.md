---
paths:
  - "apps/**/*.ex"
  - "apps/**/*.exs"
---

# Elixir Coding Rules

## Documentation & Types
- All public functions require `@spec`, `@doc`
- All modules require `@moduledoc`
- Use binary size specs: `<<_::256>>` for 32-byte hash, `<<_::160>>` for 20-byte address
- Type aliases go in the module that owns the concept (e.g., `EthCore.Types.Hash.t()`)

## Guards & Validation
- Use `defguard` for reusable validation (e.g., `is_address/1`, `is_hash/1`)
- Guard clauses in function heads over conditional logic in body

## Error Handling
- Return `{:ok, value} | {:error, atom()}` — never raise for expected errors
- Use `with/1` chains for multi-step error propagation
- Match specific error atoms, not generic `:error`

## GenServer
- Always annotate callbacks with `@impl true`
- Use `handle_continue/2` for post-init work
- Name processes via `{:via, Registry, ...}` or module name

## Style
- Max line length: 120 characters
- Max function complexity: 12 (Credo)
- Pipe chains: minimum 2 pipes to justify pipeline style
- Pattern match in function heads over case/cond when possible
- Group module attributes: moduledoc → typedoc/types → callbacks → public API → private
