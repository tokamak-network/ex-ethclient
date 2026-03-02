# Rust NIF Patterns for ex_ethclient

## Basic NIF Structure

```rust
use rustler::{Binary, Env, NifResult, Error, OwnedBinary};

#[rustler::nif]
fn hash_keccak256(data: Binary) -> Binary {
    let hash = keccak256(data.as_slice());
    let mut output = OwnedBinary::new(32).unwrap();
    output.as_mut_slice().copy_from_slice(&hash);
    output.release(env)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn execute_transaction(env: Env, tx_rlp: Binary, state: ResourceArc<DbState>) -> NifResult<Term> {
    // Long-running CPU work on dirty scheduler
    // ...
}

rustler::init!("Elixir.EthCrypto.Hash");
```

## Elixir Side

```elixir
defmodule EthCrypto.Hash do
  use Rustler, otp_app: :eth_crypto, crate: "eth_crypto_hash"

  @spec keccak256(binary()) :: binary()
  def keccak256(_data), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Type Conversion Table

| Elixir | Rust | Notes |
|--------|------|-------|
| `<<_::256>>` | `[u8; 32]` or `Binary` | 32-byte hash |
| `<<_::160>>` | `[u8; 20]` or `Binary` | 20-byte address |
| `non_neg_integer()` | `u64` | Gas, nonce |
| `binary()` | `Binary` / `OwnedBinary` | Variable-length data |
| `{:ok, term}` | `Ok(tuple)` | Success |
| `{:error, atom}` | `Err(Error::Term(box atom))` | Failure |
| `list(binary())` | `Vec<Binary>` | List of binaries |
| `map()` | `Term` (manual decode) | Complex structures |

## ResourceArc Pattern (Stateful NIFs)

Use `ResourceArc` for long-lived state like database handles:

```rust
use rustler::ResourceArc;

struct DbHandle {
    db: rocksdb::DB,
}

#[rustler::resource_impl]
impl Resource for DbHandle {}

#[rustler::nif]
fn db_open(path: String) -> NifResult<ResourceArc<DbHandle>> {
    let db = DB::open_default(&path)
        .map_err(|e| Error::Term(Box::new(e.to_string())))?;
    Ok(ResourceArc::new(DbHandle { db }))
}

#[rustler::nif(schedule = "DirtyIo")]
fn db_get(handle: ResourceArc<DbHandle>, key: Binary) -> NifResult<(Atom, Binary)> {
    match handle.db.get(key.as_slice()) {
        Ok(Some(val)) => {
            let mut bin = OwnedBinary::new(val.len()).unwrap();
            bin.as_mut_slice().copy_from_slice(&val);
            Ok((atoms::ok(), bin.release(env)))
        }
        Ok(None) => Err(Error::Term(Box::new("not_found"))),
        Err(e) => Err(Error::Term(Box::new(e.to_string()))),
    }
}
```

## Error Handling — NEVER panic

A panic in a NIF crashes the entire BEAM VM. Always use `Result` types.

```rust
// WRONG — panic crashes BEAM!
#[rustler::nif]
fn bad(data: Binary) -> Binary {
    let result = something().unwrap(); // NEVER do this
    result
}

// CORRECT — return error tuple
#[rustler::nif]
fn good(data: Binary) -> NifResult<(Atom, Binary)> {
    match something() {
        Ok(val) => Ok((atoms::ok(), val.into())),
        Err(e) => Err(Error::Term(Box::new(format!("{}", e)))),
    }
}
```

## Scheduling Guide

| Duration | Schedule | Example |
|----------|----------|---------|
| < 1ms | default (normal scheduler) | Small hashes, key derivation |
| 1ms – 100ms | `schedule = "DirtyCpu"` | EVM execution, large hashing |
| I/O bound | `schedule = "DirtyIo"` | RocksDB reads/writes |

```rust
// Normal — fast crypto ops
#[rustler::nif]
fn keccak256(data: Binary) -> Binary { /* ... */ }

// DirtyCpu — EVM execution
#[rustler::nif(schedule = "DirtyCpu")]
fn execute(env: Env, tx: Binary) -> NifResult<Term> { /* ... */ }

// DirtyIo — database operations
#[rustler::nif(schedule = "DirtyIo")]
fn db_put(handle: ResourceArc<DbHandle>, key: Binary, val: Binary) -> NifResult<Atom> { /* ... */ }
```

## Cargo.toml Setup

```toml
[package]
name = "eth_crypto_hash"
version = "0.1.0"
edition = "2021"

[lib]
name = "eth_crypto_hash"
crate-type = ["cdylib"]

[dependencies]
rustler = "0.36"
```

## mix.exs Setup

```elixir
defp deps do
  [
    {:rustler, "~> 0.36.0", runtime: false}
  ]
end
```
