use rocksdb::{Options, WriteBatch, DB};
use rustler::{Binary, Encoder, Env, NifResult, ResourceArc, Term};
use std::sync::Mutex;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        unknown_cf,
        db_error,
        lock_error,
    }
}

/// Wrapper around rocksdb::DB for use as a Rustler resource.
///
/// The Mutex ensures safe concurrent access from multiple BEAM schedulers.
/// We use Option<DB> so we can take ownership on close.
pub struct RocksDbHandle {
    db: Mutex<Option<DB>>,
}

#[rustler::resource_impl]
impl rustler::Resource for RocksDbHandle {}

/// Opens a RocksDB database at the given path with the specified column families.
///
/// Returns a resource reference to the database handle.
/// Creates column families if they don't already exist.
#[rustler::nif(schedule = "DirtyCpu")]
fn open<'a>(env: Env<'a>, path: String, column_families: Vec<String>) -> NifResult<Term<'a>> {
    let mut opts = Options::default();
    opts.create_if_missing(true);
    opts.create_missing_column_families(true);

    // Ensure "default" CF is always present (RocksDB requires it)
    let mut cfs: Vec<String> = column_families;
    if !cfs.iter().any(|cf| cf == "default") {
        cfs.push("default".to_string());
    }

    let cf_descriptors: Vec<rocksdb::ColumnFamilyDescriptor> = cfs
        .iter()
        .map(|name| {
            let cf_opts = Options::default();
            rocksdb::ColumnFamilyDescriptor::new(name.as_str(), cf_opts)
        })
        .collect();

    match DB::open_cf_descriptors(&opts, &path, cf_descriptors) {
        Ok(db) => {
            let handle = ResourceArc::new(RocksDbHandle {
                db: Mutex::new(Some(db)),
            });
            Ok((atoms::ok(), handle).encode(env))
        }
        Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
    }
}

/// Helper to execute a closure with the DB and a column family handle.
fn with_cf<'a, F>(
    env: Env<'a>,
    db_resource: &ResourceArc<RocksDbHandle>,
    cf_name: &str,
    f: F,
) -> NifResult<Term<'a>>
where
    F: FnOnce(&DB, &rocksdb::ColumnFamily) -> NifResult<Term<'a>>,
{
    let guard = match db_resource.db.lock() {
        Ok(g) => g,
        Err(_) => return Ok((atoms::error(), atoms::lock_error()).encode(env)),
    };

    let db = match guard.as_ref() {
        Some(db) => db,
        None => return Ok((atoms::error(), "database closed".to_string()).encode(env)),
    };

    let cf = match db.cf_handle(cf_name) {
        Some(cf) => cf,
        None => return Ok((atoms::error(), atoms::unknown_cf()).encode(env)),
    };

    f(db, cf)
}

/// Gets a value from the specified column family by key.
///
/// Returns {:ok, binary} if found, {:ok, nil} if not found, or {:error, reason}.
#[rustler::nif(schedule = "DirtyCpu")]
fn get<'a>(
    env: Env<'a>,
    db_resource: ResourceArc<RocksDbHandle>,
    cf_name: String,
    key: Binary<'a>,
) -> NifResult<Term<'a>> {
    with_cf(env, &db_resource, &cf_name, |db, cf| {
        match db.get_cf(cf, key.as_slice()) {
            Ok(Some(value)) => {
                let mut bin = rustler::NewBinary::new(env, value.len());
                bin.as_mut_slice().copy_from_slice(&value);
                let bin_term: Term<'a> = bin.into();
                Ok((atoms::ok(), bin_term).encode(env))
            }
            Ok(None) => {
                let nil_atom = rustler::types::atom::nil();
                Ok((atoms::ok(), nil_atom).encode(env))
            }
            Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
        }
    })
}

/// Puts a key-value pair into the specified column family.
///
/// Returns :ok on success or {:error, reason} on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn put<'a>(
    env: Env<'a>,
    db_resource: ResourceArc<RocksDbHandle>,
    cf_name: String,
    key: Binary<'a>,
    value: Binary<'a>,
) -> NifResult<Term<'a>> {
    with_cf(env, &db_resource, &cf_name, |db, cf| {
        match db.put_cf(cf, key.as_slice(), value.as_slice()) {
            Ok(()) => Ok(atoms::ok().encode(env)),
            Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
        }
    })
}

/// Deletes a key from the specified column family.
///
/// Returns :ok on success or {:error, reason} on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn delete<'a>(
    env: Env<'a>,
    db_resource: ResourceArc<RocksDbHandle>,
    cf_name: String,
    key: Binary<'a>,
) -> NifResult<Term<'a>> {
    with_cf(env, &db_resource, &cf_name, |db, cf| {
        match db.delete_cf(cf, key.as_slice()) {
            Ok(()) => Ok(atoms::ok().encode(env)),
            Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
        }
    })
}

/// Writes a batch of operations atomically.
///
/// Each operation is a 3-tuple: {cf_name, key, value} where all are binaries.
/// Returns :ok on success or {:error, reason} on failure.
#[rustler::nif(schedule = "DirtyCpu")]
fn batch_write<'a>(
    env: Env<'a>,
    db_resource: ResourceArc<RocksDbHandle>,
    operations: Vec<(String, Binary<'a>, Binary<'a>)>,
) -> NifResult<Term<'a>> {
    let guard = match db_resource.db.lock() {
        Ok(g) => g,
        Err(_) => return Ok((atoms::error(), atoms::lock_error()).encode(env)),
    };

    let db = match guard.as_ref() {
        Some(db) => db,
        None => return Ok((atoms::error(), "database closed".to_string()).encode(env)),
    };

    let mut batch = WriteBatch::default();

    for (cf_name, key, value) in &operations {
        let cf = match db.cf_handle(cf_name.as_str()) {
            Some(cf) => cf,
            None => return Ok((atoms::error(), atoms::unknown_cf()).encode(env)),
        };
        batch.put_cf(cf, key.as_slice(), value.as_slice());
    }

    match db.write(batch) {
        Ok(()) => Ok(atoms::ok().encode(env)),
        Err(e) => Ok((atoms::error(), format!("{}", e)).encode(env)),
    }
}

/// Closes the RocksDB database, releasing all resources.
///
/// After closing, any further operations on this handle will return an error.
/// Returns :ok.
#[rustler::nif(schedule = "DirtyCpu")]
fn close<'a>(env: Env<'a>, db_resource: ResourceArc<RocksDbHandle>) -> NifResult<Term<'a>> {
    let mut guard = match db_resource.db.lock() {
        Ok(g) => g,
        Err(_) => return Ok((atoms::error(), atoms::lock_error()).encode(env)),
    };

    // Drop the DB by taking it out of the Option
    let _ = guard.take();
    Ok(atoms::ok().encode(env))
}

rustler::init!("Elixir.EthStorage.RocksNative");
