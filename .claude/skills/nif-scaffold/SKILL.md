---
name: nif-scaffold
description: Generate Rustler NIF boilerplate for a new native module. Creates Cargo.toml, lib.rs, and Elixir wrapper module.
user-invocable: true
allowed-tools: Read, Write, Edit, Bash, Glob
argument-hint: <app-name> <nif-name>
---

# NIF Scaffold Generator

Create a new Rust NIF module for app `$0` named `$1`.

## Steps

1. Validate arguments:
   - `$0` must be an existing umbrella app (eth_core, eth_crypto, eth_net, eth_storage, eth_rpc)
   - `$1` should be snake_case (the NIF crate name)

2. Read the app's `mix.exs` to understand current dependencies and compilers

3. Create the Rust NIF structure:
   ```
   apps/$0/native/$1/
   ├── Cargo.toml
   └── src/
       └── lib.rs
   ```

4. `Cargo.toml` template:
   - `[package]` with name = "$1", edition = "2021"
   - `[lib]` with `crate-type = ["cdylib"]`
   - `[dependencies]` with `rustler = "0.34"`
   - Add domain-specific deps based on NIF purpose

5. `lib.rs` template:
   - `#[rustler::nif]` example function
   - `rustler::init!` macro
   - Comments for DirtyCpu scheduling pattern

6. Create Elixir wrapper module at `apps/$0/lib/$0/$1.ex`:
   - `use Rustler, otp_app: :$0, crate: "$1"`
   - Placeholder NIF functions with `:erlang.nif_error/1`
   - `@moduledoc` and `@spec` for each function

7. Update `apps/$0/mix.exs`:
   - Add `:rustler` to `deps` if not present
   - Add `rustler_crates` config
   - Add `:rustler` to `compilers` list

8. Verify the scaffold compiles: `cd apps/$0 && mix compile`
