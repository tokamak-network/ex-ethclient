use rustler::{Binary, Encoder, Env, NewBinary, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        success,
        // result map keys
        gas_used,
        output,
        // error reasons
        execution_error,
        invalid_transaction,
        invalid_address,
        out_of_gas,
    }
}

fn make_empty_binary(env: Env) -> Term {
    let binary = NewBinary::new(env, 0);
    binary.into()
}

/// Execute a simple value transfer (no smart contract).
///
/// Input: from (20 bytes), to (20 bytes), value, gas_limit, gas_price.
/// Output: {:ok, %{gas_used: u64, success: bool, output: binary}} | {:error, reason}
///
/// Currently returns mock results. Will be replaced with revm execution.
#[rustler::nif]
fn execute_simple_tx<'a>(
    env: Env<'a>,
    from: Binary<'a>,
    to: Binary<'a>,
    value: u64,
    gas_limit: u64,
    _gas_price: u64,
) -> NifResult<Term<'a>> {
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }
    if to.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    let base_gas: u64 = 21_000;

    if gas_limit < base_gas {
        return Ok((atoms::error(), atoms::out_of_gas()).encode(env));
    }

    let _ = value;

    let result_map = rustler::Term::map_new(env);
    let result_map = result_map
        .map_put(atoms::gas_used().encode(env), base_gas.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::success().encode(env), true.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::output().encode(env), make_empty_binary(env))
        .unwrap();

    Ok((atoms::ok(), result_map).encode(env))
}

/// Execute a contract call.
///
/// Input: from (20 bytes), to (20 bytes), data, value, gas_limit, gas_price.
/// Output: {:ok, %{gas_used: u64, success: bool, output: binary}} | {:error, reason}
///
/// Currently returns mock results. Will be replaced with revm execution.
#[rustler::nif]
fn execute_call<'a>(
    env: Env<'a>,
    from: Binary<'a>,
    to: Binary<'a>,
    data: Binary<'a>,
    value: u64,
    gas_limit: u64,
    _gas_price: u64,
) -> NifResult<Term<'a>> {
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }
    if to.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    let base_gas: u64 = 21_000;

    if gas_limit < base_gas {
        return Ok((atoms::error(), atoms::out_of_gas()).encode(env));
    }

    // Mock: compute gas based on data size (4 gas per zero byte, 16 per non-zero)
    let data_gas: u64 = data
        .as_slice()
        .iter()
        .map(|&b| if b == 0 { 4u64 } else { 16u64 })
        .sum();

    let total_gas = base_gas + data_gas;
    let _ = value;

    if gas_limit < total_gas {
        return Ok((atoms::error(), atoms::out_of_gas()).encode(env));
    }

    let result_map = rustler::Term::map_new(env);
    let result_map = result_map
        .map_put(atoms::gas_used().encode(env), total_gas.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::success().encode(env), true.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::output().encode(env), make_empty_binary(env))
        .unwrap();

    Ok((atoms::ok(), result_map).encode(env))
}

/// Get the version of the EVM engine.
#[rustler::nif]
fn evm_version() -> String {
    "ethvm-native/0.1.0 (mock)".to_string()
}

rustler::init!("Elixir.EthVm.Native");
