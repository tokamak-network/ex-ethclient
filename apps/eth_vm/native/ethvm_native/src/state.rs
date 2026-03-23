//! Deserializes the Elixir state binary protocol into revm's InMemoryDB.
//!
//! Binary protocol:
//! - 4 bytes: num_accounts (big-endian u32)
//! - Per account:
//!   - 20 bytes: address
//!   - 8 bytes: nonce (big-endian u64)
//!   - 32 bytes: balance (big-endian U256)
//!   - 4 bytes: code_length (big-endian u32)
//!   - N bytes: code
//!   - 4 bytes: num_storage_slots (big-endian u32)
//!   - Per slot: 32 bytes key + 32 bytes value

use revm::database::InMemoryDB;
use revm::primitives::{Address, U256};
use revm::state::{AccountInfo, Bytecode};

/// Loads pre-fetched account state from a binary blob into an InMemoryDB.
///
/// Returns Ok(()) on success, or an Err with a descriptive message on parse failure.
pub fn load_state_into_db(data: &[u8], db: &mut InMemoryDB) -> Result<(), String> {
    let mut pos = 0;

    // Parse number of accounts
    let num_accounts = read_u32(data, &mut pos)?;

    for _ in 0..num_accounts {
        // Address (20 bytes)
        if pos + 20 > data.len() {
            return Err("unexpected end of data reading address".into());
        }
        let address = Address::from_slice(&data[pos..pos + 20]);
        pos += 20;

        // Nonce (8 bytes, big-endian u64)
        let nonce = read_u64(data, &mut pos)?;

        // Balance (32 bytes, big-endian U256)
        if pos + 32 > data.len() {
            return Err("unexpected end of data reading balance".into());
        }
        let balance = U256::from_be_slice(&data[pos..pos + 32]);
        pos += 32;

        // Code length + code bytes
        let code_length = read_u32(data, &mut pos)? as usize;
        if pos + code_length > data.len() {
            return Err("unexpected end of data reading code".into());
        }
        let code_bytes = &data[pos..pos + code_length];
        pos += code_length;

        let code = if code_bytes.is_empty() {
            None
        } else {
            Some(Bytecode::new_legacy(
                revm::primitives::Bytes::copy_from_slice(code_bytes),
            ))
        };

        // Insert account info
        db.insert_account_info(
            address,
            AccountInfo {
                nonce,
                balance,
                code,
                code_hash: revm::primitives::KECCAK_EMPTY,
            },
        );

        // Storage slots
        let num_slots = read_u32(data, &mut pos)?;
        for _ in 0..num_slots {
            if pos + 64 > data.len() {
                return Err("unexpected end of data reading storage slot".into());
            }
            let slot_key = U256::from_be_slice(&data[pos..pos + 32]);
            pos += 32;
            let slot_value = U256::from_be_slice(&data[pos..pos + 32]);
            pos += 32;

            db.insert_account_storage(address, slot_key, slot_value)
                .map_err(|e| format!("failed to insert storage: {:?}", e))?;
        }
    }

    Ok(())
}

/// Reads a big-endian u32 from `data` at `pos`, advancing `pos` by 4.
fn read_u32(data: &[u8], pos: &mut usize) -> Result<u32, String> {
    if *pos + 4 > data.len() {
        return Err("unexpected end of data reading u32".into());
    }
    let val = u32::from_be_bytes([data[*pos], data[*pos + 1], data[*pos + 2], data[*pos + 3]]);
    *pos += 4;
    Ok(val)
}

/// Reads a big-endian u64 from `data` at `pos`, advancing `pos` by 8.
fn read_u64(data: &[u8], pos: &mut usize) -> Result<u64, String> {
    if *pos + 8 > data.len() {
        return Err("unexpected end of data reading u64".into());
    }
    let val = u64::from_be_bytes([
        data[*pos],
        data[*pos + 1],
        data[*pos + 2],
        data[*pos + 3],
        data[*pos + 4],
        data[*pos + 5],
        data[*pos + 6],
        data[*pos + 7],
    ]);
    *pos += 8;
    Ok(val)
}
