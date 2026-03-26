use revm::context::result::ExecutionResult;
use revm::context::{BlockEnv, Context, TxEnv};
use revm::context_interface::block::BlobExcessGasAndPrice;
use revm::context_interface::transaction::{AccessList, AccessListItem, Authorization, SignedAuthorization};
use revm::database::InMemoryDB;
use revm::handler::{MainBuilder, MainContext};
use revm::primitives::hardfork::SpecId;
use revm::primitives::{Address, Bytes, TxKind, B256, U256};
use revm::state::{AccountInfo, Bytecode};
use revm::ExecuteEvm;
use rustler::{Binary, Encoder, Env, NewBinary, NifResult, Term};

mod state;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        success,
        // result map keys
        gas_used,
        gas_refunded,
        output,
        logs,
        state_changes,
        revert_reason,
        halt_reason,
        // log keys
        address,
        topics,
        data,
        // state change keys
        nonce,
        balance,
        code,
        storage,
        // error reasons
        execution_error,
        invalid_transaction,
        invalid_address,
        invalid_access_list,
        invalid_blob_hashes,
        invalid_state_data,
        out_of_gas,
        halted,
        reverted,
    }
}

fn make_binary<'a>(env: Env<'a>, data: &[u8]) -> Term<'a> {
    let mut binary = NewBinary::new(env, data.len());
    binary.as_mut_slice().copy_from_slice(data);
    binary.into()
}

fn bytes_to_u256(bytes: &[u8]) -> U256 {
    if bytes.is_empty() {
        return U256::ZERO;
    }
    U256::from_be_slice(bytes)
}

fn u256_to_be_bytes(val: &U256) -> Vec<u8> {
    let bytes: [u8; 32] = val.to_be_bytes();
    // Trim leading zeros for compact representation
    let start = bytes.iter().position(|&b| b != 0).unwrap_or(31);
    bytes[start..].to_vec()
}

/// Determine the SpecId from block number and timestamp.
///
/// Uses mainnet fork boundaries:
///   - Prague:       timestamp >= 1_710_338_135 (TBD, use placeholder)
///   - Cancun:       timestamp >= 1_710_338_135
///   - Shanghai:     timestamp >= 1_681_338_455
///   - Paris/Merge:  block >= 15_537_394
///   - Gray Glacier: block >= 15_050_000
///   - Arrow Glacier: block >= 13_773_000
///   - London:       block >= 12_965_000
///   - Berlin:       block >= 12_244_000
///   - Istanbul:     block >= 9_069_000
///   - Petersburg:   block >= 7_280_000
///   - Constantinople: block >= 7_280_000
///   - Byzantium:    block >= 4_370_000
///   - Homestead:    block >= 1_150_000
///   - Frontier:     block >= 0
fn spec_id_for_block(block_number: u64, block_timestamp: u64) -> SpecId {
    // Post-merge forks are timestamp-based
    if block_timestamp >= 1_900_000_000 {
        SpecId::PRAGUE
    } else if block_timestamp >= 1_710_338_135 {
        SpecId::CANCUN
    } else if block_timestamp >= 1_681_338_455 {
        SpecId::SHANGHAI
    } else if block_number >= 15_537_394 {
        SpecId::MERGE
    } else if block_number >= 15_050_000 {
        SpecId::GRAY_GLACIER
    } else if block_number >= 13_773_000 {
        SpecId::ARROW_GLACIER
    } else if block_number >= 12_965_000 {
        SpecId::LONDON
    } else if block_number >= 12_244_000 {
        SpecId::BERLIN
    } else if block_number >= 9_069_000 {
        SpecId::ISTANBUL
    } else if block_number >= 7_280_000 {
        SpecId::PETERSBURG
    } else if block_number >= 4_370_000 {
        SpecId::BYZANTIUM
    } else if block_number >= 2_675_000 {
        SpecId::SPURIOUS_DRAGON
    } else if block_number >= 2_463_000 {
        SpecId::TANGERINE
    } else if block_number >= 1_150_000 {
        SpecId::HOMESTEAD
    } else {
        SpecId::FRONTIER
    }
}

/// Execute a transaction with the real revm EVM engine.
///
/// Input:
///   from (20 bytes), to (20 bytes, empty for contract creation),
///   value_bytes (big-endian U256), gas_limit, gas_price_bytes (big-endian U256),
///   data (calldata), code (contract bytecode at `to`), nonce, balance_bytes (big-endian U256)
///
/// Output:
///   {:ok, %{gas_used, gas_refunded, success, output, logs, state_changes}}
///   | {:error, reason}
#[rustler::nif(schedule = "DirtyCpu")]
fn execute_tx<'a>(
    env: Env<'a>,
    from: Binary<'a>,
    to: Binary<'a>,
    value_bytes: Binary<'a>,
    gas_limit: u64,
    gas_price_bytes: Binary<'a>,
    input_data: Binary<'a>,
    contract_code: Binary<'a>,
    tx_nonce: u64,
    balance_bytes: Binary<'a>,
) -> NifResult<Term<'a>> {
    // Validate from address
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    // Parse addresses
    let from_addr = Address::from_slice(from.as_slice());

    let tx_kind = if to.is_empty() {
        TxKind::Create
    } else if to.len() == 20 {
        TxKind::Call(Address::from_slice(to.as_slice()))
    } else {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    };

    let value = bytes_to_u256(value_bytes.as_slice());
    let gas_price = bytes_to_u256(gas_price_bytes.as_slice());
    let sender_balance = bytes_to_u256(balance_bytes.as_slice());
    let calldata = Bytes::copy_from_slice(input_data.as_slice());

    // Build an in-memory database and insert accounts
    let mut db = InMemoryDB::default();

    // Insert sender account
    db.insert_account_info(
        from_addr,
        AccountInfo {
            nonce: tx_nonce,
            balance: sender_balance,
            code: None,
            code_hash: revm::primitives::KECCAK_EMPTY,
        },
    );

    // Insert target account with code if provided
    if let TxKind::Call(to_addr) = tx_kind {
        if !contract_code.is_empty() {
            let bytecode = Bytecode::new_legacy(Bytes::copy_from_slice(contract_code.as_slice()));
            db.insert_account_info(
                to_addr,
                AccountInfo {
                    nonce: 0,
                    balance: U256::ZERO,
                    code: Some(bytecode),
                    code_hash: revm::primitives::KECCAK_EMPTY,
                },
            );
        }
    }

    // Build the EVM context
    let gas_price_u128: u128 = gas_price.try_into().unwrap_or(0u128);

    let ctx = Context::mainnet()
        .with_db(db)
        .modify_cfg_chained(|cfg| {
            cfg.spec = SpecId::CANCUN;
            cfg.disable_balance_check = true;
            cfg.disable_block_gas_limit = true;
            cfg.disable_base_fee = true;
            cfg.disable_eip3607 = true;
            cfg.disable_nonce_check = true;
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.caller = from_addr;
            tx.kind = tx_kind;
            tx.value = value;
            tx.gas_limit = gas_limit;
            tx.gas_price = gas_price_u128;
            tx.data = calldata;
            tx.nonce = tx_nonce;
            tx.chain_id = Some(1);
        });

    let mut evm = ctx.build_mainnet();

    // Execute
    match evm.replay() {
        Ok(result_and_state) => Ok(build_result_term(
            env,
            &result_and_state.result,
            &result_and_state.state,
        )),
        Err(e) => Ok((
            atoms::error(),
            format!("{:?}", e).encode(env),
        )
            .encode(env)),
    }
}

/// Execute a simple value transfer (no smart contract).
/// Kept for backwards compatibility. Delegates to execute_tx internally.
#[rustler::nif(schedule = "DirtyCpu")]
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

    let from_addr = Address::from_slice(from.as_slice());
    let to_addr = Address::from_slice(to.as_slice());

    let mut db = InMemoryDB::default();

    // Give sender enough balance
    let sender_balance = U256::from(value) + U256::from(gas_limit) * U256::from(1_000_000_000u64);
    db.insert_account_info(
        from_addr,
        AccountInfo {
            nonce: 0,
            balance: sender_balance,
            code: None,
            code_hash: revm::primitives::KECCAK_EMPTY,
        },
    );

    let ctx = Context::mainnet()
        .with_db(db)
        .modify_cfg_chained(|cfg| {
            cfg.spec = SpecId::CANCUN;
            cfg.disable_balance_check = true;
            cfg.disable_block_gas_limit = true;
            cfg.disable_base_fee = true;
            cfg.disable_eip3607 = true;
            cfg.disable_nonce_check = true;
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.caller = from_addr;
            tx.kind = TxKind::Call(to_addr);
            tx.value = U256::from(value);
            tx.gas_limit = gas_limit;
            tx.gas_price = 0;
            tx.nonce = 0;
            tx.chain_id = Some(1);
        });

    let mut evm = ctx.build_mainnet();

    match evm.replay() {
        Ok(result_and_state) => {
            let (is_success, gas_used_val, output_bytes) = match &result_and_state.result {
                ExecutionResult::Success {
                    gas_used, output, ..
                } => (true, *gas_used, output.data().to_vec()),
                ExecutionResult::Revert { gas_used, output } => {
                    (false, *gas_used, output.to_vec())
                }
                ExecutionResult::Halt { gas_used, .. } => (false, *gas_used, vec![]),
            };

            let result_map = Term::map_new(env);
            let result_map = result_map
                .map_put(atoms::gas_used().encode(env), gas_used_val.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(atoms::success().encode(env), is_success.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(atoms::output().encode(env), make_binary(env, &output_bytes))
                .unwrap();

            Ok((atoms::ok(), result_map).encode(env))
        }
        Err(_e) => Ok((atoms::error(), atoms::execution_error()).encode(env)),
    }
}

/// Execute a contract call. Kept for backwards compatibility.
#[rustler::nif(schedule = "DirtyCpu")]
fn execute_call<'a>(
    env: Env<'a>,
    from: Binary<'a>,
    to: Binary<'a>,
    input_data: Binary<'a>,
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

    let from_addr = Address::from_slice(from.as_slice());
    let to_addr = Address::from_slice(to.as_slice());

    let mut db = InMemoryDB::default();

    let sender_balance = U256::from(value) + U256::from(gas_limit) * U256::from(1_000_000_000u64);
    db.insert_account_info(
        from_addr,
        AccountInfo {
            nonce: 0,
            balance: sender_balance,
            code: None,
            code_hash: revm::primitives::KECCAK_EMPTY,
        },
    );

    let calldata = Bytes::copy_from_slice(input_data.as_slice());

    let ctx = Context::mainnet()
        .with_db(db)
        .modify_cfg_chained(|cfg| {
            cfg.spec = SpecId::CANCUN;
            cfg.disable_balance_check = true;
            cfg.disable_block_gas_limit = true;
            cfg.disable_base_fee = true;
            cfg.disable_eip3607 = true;
            cfg.disable_nonce_check = true;
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.caller = from_addr;
            tx.kind = TxKind::Call(to_addr);
            tx.value = U256::from(value);
            tx.gas_limit = gas_limit;
            tx.gas_price = 0;
            tx.data = calldata;
            tx.nonce = 0;
            tx.chain_id = Some(1);
        });

    let mut evm = ctx.build_mainnet();

    match evm.replay() {
        Ok(result_and_state) => {
            let (is_success, gas_used_val, output_bytes) = match &result_and_state.result {
                ExecutionResult::Success {
                    gas_used, output, ..
                } => (true, *gas_used, output.data().to_vec()),
                ExecutionResult::Revert { gas_used, output } => {
                    (false, *gas_used, output.to_vec())
                }
                ExecutionResult::Halt { gas_used, .. } => (false, *gas_used, vec![]),
            };

            let result_map = Term::map_new(env);
            let result_map = result_map
                .map_put(atoms::gas_used().encode(env), gas_used_val.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(atoms::success().encode(env), is_success.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(atoms::output().encode(env), make_binary(env, &output_bytes))
                .unwrap();

            Ok((atoms::ok(), result_map).encode(env))
        }
        Err(_e) => Ok((atoms::error(), atoms::execution_error()).encode(env)),
    }
}

/// Parse a binary-encoded access list into revm's AccessList type.
///
/// Binary format:
///   4 bytes: num_entries (u32 big-endian)
///   Per entry:
///     20 bytes: address
///     4 bytes: num_keys (u32 big-endian)
///     N * 32 bytes: storage keys
///
/// Returns None if the binary is malformed.
fn parse_access_list(data: &[u8]) -> Option<AccessList> {
    if data.is_empty() {
        return Some(AccessList(vec![]));
    }

    if data.len() < 4 {
        return None;
    }

    let num_entries = u32::from_be_bytes([data[0], data[1], data[2], data[3]]) as usize;
    let mut offset = 4usize;
    let mut items = Vec::with_capacity(num_entries);

    for _ in 0..num_entries {
        // Need at least 20 (address) + 4 (num_keys) bytes
        if offset + 24 > data.len() {
            return None;
        }

        let address = Address::from_slice(&data[offset..offset + 20]);
        offset += 20;

        let num_keys =
            u32::from_be_bytes([data[offset], data[offset + 1], data[offset + 2], data[offset + 3]])
                as usize;
        offset += 4;

        // Need num_keys * 32 bytes for storage keys
        if offset + num_keys * 32 > data.len() {
            return None;
        }

        let mut storage_keys = Vec::with_capacity(num_keys);
        for _ in 0..num_keys {
            let key = B256::from_slice(&data[offset..offset + 32]);
            storage_keys.push(key);
            offset += 32;
        }

        items.push(AccessListItem {
            address,
            storage_keys,
        });
    }

    Some(AccessList(items))
}

/// Parse concatenated 32-byte blob versioned hashes.
///
/// Returns None if the data length is not a multiple of 32.
fn parse_blob_hashes(data: &[u8]) -> Option<Vec<B256>> {
    if data.is_empty() {
        return Some(vec![]);
    }
    if data.len() % 32 != 0 {
        return None;
    }

    let count = data.len() / 32;
    let mut hashes = Vec::with_capacity(count);
    for i in 0..count {
        hashes.push(B256::from_slice(&data[i * 32..(i + 1) * 32]));
    }
    Some(hashes)
}

/// Parse EIP-7702 authorization list from binary data.
///
/// Format: concatenated entries of (chain_id:32 + address:20 + nonce:8 + y_parity:1 + r:32 + s:32) = 125 bytes each
fn parse_authorization_list(data: &[u8]) -> Option<Vec<SignedAuthorization>> {
    if data.is_empty() {
        return Some(vec![]);
    }
    let entry_size = 32 + 20 + 8 + 1 + 32 + 32; // 125 bytes
    if data.len() % entry_size != 0 {
        return None;
    }

    let count = data.len() / entry_size;
    let mut auth_list = Vec::with_capacity(count);

    for i in 0..count {
        let offset = i * entry_size;
        let chain_id = U256::from_be_slice(&data[offset..offset + 32]);
        let address = Address::from_slice(&data[offset + 32..offset + 52]);
        let nonce = u64::from_be_bytes(data[offset + 52..offset + 60].try_into().ok()?);
        let y_parity = data[offset + 60];
        let r = U256::from_be_slice(&data[offset + 61..offset + 93]);
        let s = U256::from_be_slice(&data[offset + 93..offset + 125]);

        let inner = Authorization { chain_id, address, nonce };
        auth_list.push(SignedAuthorization::new_unchecked(inner, y_parity, r, s));
    }
    Some(auth_list)
}

/// Shared helper to build result terms from EVM execution output.
fn build_result_term<'a>(
    env: Env<'a>,
    exec_result: &ExecutionResult,
    evm_state: &revm::state::EvmState,
) -> Term<'a> {
    let (is_success, gas_used_val, gas_refunded_val, output_bytes, log_list, revert_data, halt_info) =
        match exec_result {
            ExecutionResult::Success {
                gas_used,
                gas_refunded,
                logs: result_logs,
                output,
                ..
            } => (
                true,
                *gas_used,
                *gas_refunded,
                output.data().to_vec(),
                result_logs.clone(),
                None,
                None,
            ),
            ExecutionResult::Revert { gas_used, output } => (
                false,
                *gas_used,
                0u64,
                output.to_vec(),
                vec![],
                Some(output.to_vec()),
                None,
            ),
            ExecutionResult::Halt {
                gas_used, reason, ..
            } => (
                false,
                *gas_used,
                0u64,
                vec![],
                vec![],
                None,
                Some(format!("{:?}", reason)),
            ),
        };

    // Build logs list
    let logs_term: Vec<Term<'a>> = log_list
        .iter()
        .map(|log| {
            let addr_term = make_binary(env, log.address.as_slice());
            let topics_term: Vec<Term<'a>> = log
                .data
                .topics()
                .iter()
                .map(|t| make_binary(env, t.as_slice()))
                .collect();
            let data_term = make_binary(env, log.data.data.as_ref());

            let log_map = Term::map_new(env);
            let log_map = log_map
                .map_put(atoms::address().encode(env), addr_term)
                .unwrap();
            let log_map = log_map
                .map_put(atoms::topics().encode(env), topics_term.encode(env))
                .unwrap();
            let log_map = log_map
                .map_put(atoms::data().encode(env), data_term)
                .unwrap();
            log_map
        })
        .collect();

    // Build state_changes map: %{address_binary => %{nonce, balance, code, storage}}
    let state_changes_map = Term::map_new(env);
    let state_changes_map =
        evm_state
            .iter()
            .fold(state_changes_map, |acc, (addr, account)| {
                let addr_bin = make_binary(env, addr.as_slice());

                let acct_map = Term::map_new(env);
                let acct_map = acct_map
                    .map_put(
                        atoms::nonce().encode(env),
                        account.info.nonce.encode(env),
                    )
                    .unwrap();

                let balance_bin = make_binary(env, &u256_to_be_bytes(&account.info.balance));
                let acct_map = acct_map
                    .map_put(atoms::balance().encode(env), balance_bin)
                    .unwrap();

                // Include contract code if present.
                // Use original_bytes() to get un-padded bytecode (bytecode()
                // returns analysis-padded bytes which would produce wrong
                // code_hash in the state trie).
                let code_bin = match &account.info.code {
                    Some(bytecode) => make_binary(env, bytecode.original_bytes().as_ref()),
                    None => make_binary(env, &[]),
                };
                let acct_map = acct_map
                    .map_put(atoms::code().encode(env), code_bin)
                    .unwrap();

                // Storage changes
                let storage_map = Term::map_new(env);
                let storage_map =
                    account
                        .storage
                        .iter()
                        .fold(storage_map, |sacc, (slot, sval)| {
                            let slot_bin = make_binary(env, &u256_to_be_bytes(slot));
                            let val_bin =
                                make_binary(env, &u256_to_be_bytes(&sval.present_value()));
                            sacc.map_put(slot_bin, val_bin).unwrap_or(sacc)
                        });

                let acct_map = acct_map
                    .map_put(atoms::storage().encode(env), storage_map)
                    .unwrap();

                acc.map_put(addr_bin, acct_map).unwrap_or(acc)
            });

    // Build result map
    let result_map = Term::map_new(env);
    let result_map = result_map
        .map_put(atoms::gas_used().encode(env), gas_used_val.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(
            atoms::gas_refunded().encode(env),
            gas_refunded_val.encode(env),
        )
        .unwrap();
    let result_map = result_map
        .map_put(atoms::success().encode(env), is_success.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::output().encode(env), make_binary(env, &output_bytes))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::logs().encode(env), logs_term.encode(env))
        .unwrap();
    let result_map = result_map
        .map_put(atoms::state_changes().encode(env), state_changes_map)
        .unwrap();

    // Add revert reason if present
    let result_map = if let Some(revert_bytes) = revert_data {
        result_map
            .map_put(
                atoms::revert_reason().encode(env),
                make_binary(env, &revert_bytes),
            )
            .unwrap()
    } else {
        result_map
    };

    // Add halt reason if present
    let result_map = if let Some(halt_str) = halt_info {
        result_map
            .map_put(atoms::halt_reason().encode(env), halt_str.encode(env))
            .unwrap()
    } else {
        result_map
    };

    (atoms::ok(), result_map).encode(env)
}

/// Execute a transaction with full type support (Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702).
///
/// Input:
///   tx_type: u8 (0=Legacy, 1=EIP-2930, 2=EIP-1559, 3=EIP-4844, 4=EIP-7702)
///   from (20 bytes), to (20 bytes, empty for contract creation),
///   value_bytes (big-endian U256), gas_limit, gas_price_bytes (big-endian U256),
///   max_priority_fee_bytes (big-endian U256, empty if not applicable),
///   max_fee_per_blob_gas_bytes (big-endian U256, empty if not applicable),
///   data (calldata), code (contract bytecode at `to`),
///   nonce, balance_bytes (big-endian U256),
///   access_list_data (binary-encoded access list),
///   blob_hashes_data (concatenated 32-byte hashes)
///
/// Output:
///   {:ok, %{gas_used, gas_refunded, success, output, logs, state_changes}}
///   | {:error, reason}
#[rustler::nif(schedule = "DirtyCpu")]
fn execute_tx_v2<'a>(
    env: Env<'a>,
    tx_type: u8,
    from: Binary<'a>,
    to: Binary<'a>,
    value_bytes: Binary<'a>,
    gas_limit: u64,
    gas_price_bytes: Binary<'a>,
    max_priority_fee_bytes: Binary<'a>,
    max_fee_per_blob_gas_bytes: Binary<'a>,
    input_data: Binary<'a>,
    contract_code: Binary<'a>,
    tx_nonce: u64,
    balance_bytes: Binary<'a>,
    access_list_data: Binary<'a>,
    blob_hashes_data: Binary<'a>,
) -> NifResult<Term<'a>> {
    // Validate from address
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    // Parse addresses
    let from_addr = Address::from_slice(from.as_slice());

    let tx_kind = if to.is_empty() {
        TxKind::Create
    } else if to.len() == 20 {
        TxKind::Call(Address::from_slice(to.as_slice()))
    } else {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    };

    let value = bytes_to_u256(value_bytes.as_slice());
    let gas_price = bytes_to_u256(gas_price_bytes.as_slice());
    let sender_balance = bytes_to_u256(balance_bytes.as_slice());
    let calldata = Bytes::copy_from_slice(input_data.as_slice());

    // Parse access list
    let access_list = match parse_access_list(access_list_data.as_slice()) {
        Some(al) => al,
        None => return Ok((atoms::error(), atoms::invalid_access_list()).encode(env)),
    };

    // Parse blob hashes
    let blob_hashes = match parse_blob_hashes(blob_hashes_data.as_slice()) {
        Some(bh) => bh,
        None => return Ok((atoms::error(), atoms::invalid_blob_hashes()).encode(env)),
    };

    // Parse priority fee and blob gas fee
    let gas_priority_fee = if max_priority_fee_bytes.is_empty() {
        None
    } else {
        let val = bytes_to_u256(max_priority_fee_bytes.as_slice());
        Some(val.try_into().unwrap_or(0u128))
    };

    let max_fee_per_blob_gas: u128 = if max_fee_per_blob_gas_bytes.is_empty() {
        0
    } else {
        bytes_to_u256(max_fee_per_blob_gas_bytes.as_slice())
            .try_into()
            .unwrap_or(0u128)
    };

    let gas_price_u128: u128 = gas_price.try_into().unwrap_or(0u128);

    // Build an in-memory database and insert accounts
    let mut db = InMemoryDB::default();

    // Insert sender account
    db.insert_account_info(
        from_addr,
        AccountInfo {
            nonce: tx_nonce,
            balance: sender_balance,
            code: None,
            code_hash: revm::primitives::KECCAK_EMPTY,
        },
    );

    // Insert target account with code if provided
    if let TxKind::Call(to_addr) = tx_kind {
        if !contract_code.is_empty() {
            let bytecode = Bytecode::new_legacy(Bytes::copy_from_slice(contract_code.as_slice()));
            db.insert_account_info(
                to_addr,
                AccountInfo {
                    nonce: 0,
                    balance: U256::ZERO,
                    code: Some(bytecode),
                    code_hash: revm::primitives::KECCAK_EMPTY,
                },
            );
        }
    }

    // Determine the spec ID based on tx type
    let spec_id = match tx_type {
        4 => SpecId::PRAGUE,
        _ => SpecId::CANCUN,
    };

    // Build the EVM context
    let ctx = Context::mainnet()
        .with_db(db)
        .modify_cfg_chained(|cfg| {
            cfg.spec = spec_id;
            cfg.disable_balance_check = true;
            cfg.disable_block_gas_limit = true;
            cfg.disable_base_fee = true;
            cfg.disable_eip3607 = true;
            cfg.disable_nonce_check = true;
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.tx_type = tx_type;
            tx.caller = from_addr;
            tx.kind = tx_kind;
            tx.value = value;
            tx.gas_limit = gas_limit;
            tx.gas_price = gas_price_u128;
            tx.data = calldata;
            tx.nonce = tx_nonce;
            tx.chain_id = Some(1);
            tx.access_list = access_list;
            tx.gas_priority_fee = gas_priority_fee;
            tx.blob_hashes = blob_hashes;
            tx.max_fee_per_blob_gas = max_fee_per_blob_gas;
            // authorization_list left empty for now (EIP-7702)
        });

    let mut evm = ctx.build_mainnet();

    // Execute
    match evm.replay() {
        Ok(result_and_state) => {
            Ok(build_result_term(env, &result_and_state.result, &result_and_state.state))
        }
        Err(e) => Ok((
            atoms::error(),
            format!("{:?}", e).encode(env),
        )
            .encode(env)),
    }
}

/// Execute a transaction with full block context and pre-loaded state.
///
/// This is the primary NIF for real mainnet transaction execution. It receives:
/// - Block-level context (number, timestamp, coinbase, base fee, prevrandao, excess blob gas)
/// - Full transaction type support (Legacy through EIP-7702)
/// - Pre-serialized account state (via StateLoader binary protocol)
/// - Access list and blob hashes
///
/// The SpecId is determined automatically from block number and timestamp using
/// mainnet fork boundaries.
///
/// Output:
///   {:ok, %{gas_used, gas_refunded, success, output, logs, state_changes,
///           revert_reason (optional), halt_reason (optional)}}
///   | {:error, reason}
#[rustler::nif(schedule = "DirtyCpu")]
fn execute_tx_v3<'a>(
    env: Env<'a>,
    // Block context
    block_number: u64,
    block_timestamp: u64,
    coinbase: Binary<'a>,
    base_fee: u64,
    prev_randao: Binary<'a>,
    block_gas_limit: u64,
    excess_blob_gas: u64,
    // Transaction fields
    tx_type: u8,
    from: Binary<'a>,
    to: Binary<'a>,
    value_bytes: Binary<'a>,
    gas_limit: u64,
    gas_price_bytes: Binary<'a>,
    max_priority_fee_bytes: Binary<'a>,
    max_fee_per_blob_gas_bytes: Binary<'a>,
    input_data: Binary<'a>,
    tx_nonce: u64,
    // State
    state_data: Binary<'a>,
    access_list_data: Binary<'a>,
    blob_hashes_data: Binary<'a>,
    authorization_list_data: Binary<'a>,
) -> NifResult<Term<'a>> {
    // Validate from address
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    // Parse coinbase address
    let coinbase_addr = if coinbase.len() == 20 {
        Address::from_slice(coinbase.as_slice())
    } else if coinbase.is_empty() {
        Address::ZERO
    } else {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    };

    // Parse from address
    let from_addr = Address::from_slice(from.as_slice());

    // Parse to address / contract creation
    let tx_kind = if to.is_empty() {
        TxKind::Create
    } else if to.len() == 20 {
        TxKind::Call(Address::from_slice(to.as_slice()))
    } else {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    };

    let value = bytes_to_u256(value_bytes.as_slice());
    let gas_price = bytes_to_u256(gas_price_bytes.as_slice());
    let calldata = Bytes::copy_from_slice(input_data.as_slice());

    // Parse access list
    let access_list = match parse_access_list(access_list_data.as_slice()) {
        Some(al) => al,
        None => return Ok((atoms::error(), atoms::invalid_access_list()).encode(env)),
    };

    // Parse blob hashes
    let blob_hashes = match parse_blob_hashes(blob_hashes_data.as_slice()) {
        Some(bh) => bh,
        None => return Ok((atoms::error(), atoms::invalid_blob_hashes()).encode(env)),
    };

    // Parse EIP-7702 authorization list
    let authorization_list = match parse_authorization_list(authorization_list_data.as_slice()) {
        Some(al) => al,
        None => return Ok((atoms::error(), "invalid_authorization_list".encode(env)).encode(env)),
    };

    // Parse priority fee and blob gas fee
    let gas_priority_fee = if max_priority_fee_bytes.is_empty() {
        None
    } else {
        let val = bytes_to_u256(max_priority_fee_bytes.as_slice());
        Some(val.try_into().unwrap_or(0u128))
    };

    let max_fee_per_blob_gas: u128 = if max_fee_per_blob_gas_bytes.is_empty() {
        0
    } else {
        bytes_to_u256(max_fee_per_blob_gas_bytes.as_slice())
            .try_into()
            .unwrap_or(0u128)
    };

    let gas_price_u128: u128 = gas_price.try_into().unwrap_or(0u128);

    // Parse prevrandao
    let prevrandao = if prev_randao.len() == 32 {
        Some(B256::from_slice(prev_randao.as_slice()))
    } else {
        None
    };

    // Build an in-memory database and load pre-fetched state
    let mut db = InMemoryDB::default();
    let has_state = !state_data.is_empty();

    if has_state {
        if let Err(_e) = state::load_state_into_db(state_data.as_slice(), &mut db) {
            return Ok((atoms::error(), atoms::invalid_state_data()).encode(env));
        }
    }

    // Determine the spec ID from block context
    let spec_id = spec_id_for_block(block_number, block_timestamp);

    // Build block environment
    let blob_excess = if excess_blob_gas > 0 || spec_id >= SpecId::CANCUN {
        Some(BlobExcessGasAndPrice::new(
            excess_blob_gas,
            spec_id >= SpecId::PRAGUE,
        ))
    } else {
        None
    };

    let block_env = BlockEnv {
        number: block_number,
        beneficiary: coinbase_addr,
        timestamp: block_timestamp,
        gas_limit: block_gas_limit,
        basefee: base_fee,
        difficulty: U256::ZERO,
        prevrandao,
        blob_excess_gas_and_price: blob_excess,
    };

    // Build the EVM context with real block environment.
    // When state is provided, enable full validation (balance, nonce, base fee).
    // When no state is provided, disable validation for compatibility (tests, etc).
    let ctx = Context::mainnet()
        .with_db(db)
        .with_block(block_env)
        .modify_cfg_chained(|cfg| {
            cfg.spec = spec_id;
            if has_state {
                // Real execution: validate everything
                cfg.disable_balance_check = false;
                cfg.disable_block_gas_limit = false;
                cfg.disable_base_fee = false;
                cfg.disable_nonce_check = false;
            } else {
                // No state provided: disable checks for compatibility
                cfg.disable_balance_check = true;
                cfg.disable_block_gas_limit = true;
                cfg.disable_base_fee = true;
                cfg.disable_nonce_check = true;
            }
            cfg.disable_eip3607 = true; // Always: allows EOAs with code
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.tx_type = tx_type;
            tx.caller = from_addr;
            tx.kind = tx_kind;
            tx.value = value;
            tx.gas_limit = gas_limit;
            tx.gas_price = gas_price_u128;
            tx.data = calldata;
            tx.nonce = tx_nonce;
            tx.chain_id = Some(1);
            tx.access_list = access_list;
            tx.gas_priority_fee = gas_priority_fee;
            tx.blob_hashes = blob_hashes;
            tx.max_fee_per_blob_gas = max_fee_per_blob_gas;
            tx.authorization_list = authorization_list;
        });

    let mut evm = ctx.build_mainnet();

    // Execute
    match evm.replay() {
        Ok(result_and_state) => {
            Ok(build_result_term(env, &result_and_state.result, &result_and_state.state))
        }
        Err(e) => Ok((
            atoms::error(),
            format!("{:?}", e).encode(env),
        )
            .encode(env)),
    }
}

/// Execute a transaction with pre-loaded state (simplified version).
///
/// Uses the state binary protocol to load accounts into the EVM database
/// before execution. Validation checks are disabled for testing flexibility.
///
/// Input:
///   state_data: binary-encoded state (see state.rs for protocol)
///   from (20 bytes), to (20 bytes, empty for contract creation),
///   value_bytes (32-byte big-endian U256), gas_limit,
///   gas_price_bytes (32-byte big-endian U256),
///   data (calldata), nonce
///
/// Output:
///   {:ok, %{success, gas_used, gas_refunded, output, logs, state_changes}}
///   | {:error, reason}
#[rustler::nif(schedule = "DirtyCpu")]
fn execute_tx_with_state<'a>(
    env: Env<'a>,
    state_data: Binary<'a>,
    from: Binary<'a>,
    to: Binary<'a>,
    value_bytes: Binary<'a>,
    gas_limit: u64,
    gas_price_bytes: Binary<'a>,
    input_data: Binary<'a>,
    tx_nonce: u64,
) -> NifResult<Term<'a>> {
    // Validate from address
    if from.len() != 20 {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    }

    let from_addr = Address::from_slice(from.as_slice());

    let tx_kind = if to.is_empty() {
        TxKind::Create
    } else if to.len() == 20 {
        TxKind::Call(Address::from_slice(to.as_slice()))
    } else {
        return Ok((atoms::error(), atoms::invalid_address()).encode(env));
    };

    let value = bytes_to_u256(value_bytes.as_slice());
    let gas_price = bytes_to_u256(gas_price_bytes.as_slice());
    let gas_price_u128: u128 = gas_price.try_into().unwrap_or(0u128);
    let calldata = Bytes::copy_from_slice(input_data.as_slice());

    // Load pre-fetched state into InMemoryDB
    let mut db = InMemoryDB::default();

    if !state_data.is_empty() {
        if let Err(_e) = state::load_state_into_db(state_data.as_slice(), &mut db) {
            return Ok((atoms::error(), atoms::invalid_state_data()).encode(env));
        }
    }

    // Build the EVM context with loaded state
    let ctx = Context::mainnet()
        .with_db(db)
        .modify_cfg_chained(|cfg| {
            cfg.spec = SpecId::CANCUN;
            cfg.disable_balance_check = true;
            cfg.disable_block_gas_limit = true;
            cfg.disable_base_fee = true;
            cfg.disable_eip3607 = true;
            cfg.disable_nonce_check = true;
        })
        .modify_tx_chained(|tx: &mut TxEnv| {
            tx.caller = from_addr;
            tx.kind = tx_kind;
            tx.value = value;
            tx.gas_limit = gas_limit;
            tx.gas_price = gas_price_u128;
            tx.data = calldata;
            tx.nonce = tx_nonce;
            tx.chain_id = Some(1);
        });

    let mut evm = ctx.build_mainnet();

    // Execute
    match evm.replay() {
        Ok(result_and_state) => {
            // Convert to the legacy format expected by nif_state_test
            let exec_result = &result_and_state.result;
            let evm_state = &result_and_state.state;

            let (is_success, gas_used_val, gas_refunded_val, output_bytes, log_list) =
                match exec_result {
                    ExecutionResult::Success {
                        gas_used,
                        gas_refunded,
                        logs: result_logs,
                        output,
                        ..
                    } => (
                        true,
                        *gas_used,
                        *gas_refunded,
                        output.data().to_vec(),
                        result_logs.clone(),
                    ),
                    ExecutionResult::Revert { gas_used, output } => {
                        (false, *gas_used, 0u64, output.to_vec(), vec![])
                    }
                    ExecutionResult::Halt { gas_used, .. } => {
                        (false, *gas_used, 0u64, vec![], vec![])
                    }
                };

            // Build state_changes map
            let state_changes_map = Term::map_new(env);
            let state_changes_map =
                evm_state
                    .iter()
                    .fold(state_changes_map, |acc, (addr, account)| {
                        let addr_bin = make_binary(env, addr.as_slice());

                        let acct_map = Term::map_new(env);
                        let acct_map = acct_map
                            .map_put(
                                atoms::nonce().encode(env),
                                account.info.nonce.encode(env),
                            )
                            .unwrap();

                        let balance_bin =
                            make_binary(env, &u256_to_be_bytes(&account.info.balance));
                        let acct_map = acct_map
                            .map_put(atoms::balance().encode(env), balance_bin)
                            .unwrap();

                        let storage_map = Term::map_new(env);
                        let storage_map =
                            account
                                .storage
                                .iter()
                                .fold(storage_map, |sacc, (slot, sval)| {
                                    let slot_bin = make_binary(env, &u256_to_be_bytes(slot));
                                    let val_bin =
                                        make_binary(env, &u256_to_be_bytes(&sval.present_value()));
                                    sacc.map_put(slot_bin, val_bin).unwrap_or(sacc)
                                });

                        let acct_map = acct_map
                            .map_put(atoms::storage().encode(env), storage_map)
                            .unwrap();

                        acc.map_put(addr_bin, acct_map).unwrap_or(acc)
                    });

            // Return as a struct-like map with atom keys (for compatibility with existing tests)
            let result_map = Term::map_new(env);
            let success_atom = rustler::types::atom::Atom::from_str(env, "success").unwrap();
            let gas_used_atom = rustler::types::atom::Atom::from_str(env, "gas_used").unwrap();
            let gas_refunded_atom =
                rustler::types::atom::Atom::from_str(env, "gas_refunded").unwrap();
            let output_atom = rustler::types::atom::Atom::from_str(env, "output").unwrap();
            let logs_atom = rustler::types::atom::Atom::from_str(env, "logs").unwrap();
            let state_changes_atom =
                rustler::types::atom::Atom::from_str(env, "state_changes").unwrap();

            let logs_term: Vec<Term<'a>> = log_list
                .iter()
                .map(|log| {
                    let addr_term = make_binary(env, log.address.as_slice());
                    let topics_term: Vec<Term<'a>> = log
                        .data
                        .topics()
                        .iter()
                        .map(|t| make_binary(env, t.as_slice()))
                        .collect();
                    let data_term = make_binary(env, log.data.data.as_ref());

                    let log_map = Term::map_new(env);
                    let log_map = log_map
                        .map_put(atoms::address().encode(env), addr_term)
                        .unwrap();
                    let log_map = log_map
                        .map_put(atoms::topics().encode(env), topics_term.encode(env))
                        .unwrap();
                    let log_map = log_map
                        .map_put(atoms::data().encode(env), data_term)
                        .unwrap();
                    log_map
                })
                .collect();

            let result_map = result_map
                .map_put(success_atom.encode(env), is_success.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(gas_used_atom.encode(env), gas_used_val.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(
                    gas_refunded_atom.encode(env),
                    gas_refunded_val.encode(env),
                )
                .unwrap();
            let result_map = result_map
                .map_put(output_atom.encode(env), make_binary(env, &output_bytes))
                .unwrap();
            let result_map = result_map
                .map_put(logs_atom.encode(env), logs_term.encode(env))
                .unwrap();
            let result_map = result_map
                .map_put(state_changes_atom.encode(env), state_changes_map)
                .unwrap();

            Ok((atoms::ok(), result_map).encode(env))
        }
        Err(e) => Ok((
            atoms::error(),
            format!("{:?}", e).encode(env),
        )
            .encode(env)),
    }
}

/// Get the version of the EVM engine.
#[rustler::nif]
fn evm_version() -> String {
    "ethvm-native/0.2.0 (revm 22)".to_string()
}

rustler::init!("Elixir.EthVm.Native");
