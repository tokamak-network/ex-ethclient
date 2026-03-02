# Phase Roadmap

## Phase 1: Core Types & Signing ✅

- 5 transaction types encoding/decoding (Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702)
- EIP-2 signature normalization (s in lower half of curve order)
- RLP codec for all core types
- 130 tests passing
- **Completion criteria**: All tx types round-trip test pass

## Phase 3: Networking ✅

- DiscV4 discovery protocol (ping/pong, findnode/neighbours, ENR)
- RLPx transport (EIP-8 handshake, ECIES encryption, frame codec)
- eth/68 protocol handler (status, block headers, transactions)
- CLI: `mix eth_net.start --port 30303 --datadir ./data`
- 208 total tests passing
- **Completion criteria**: Successful handshake with live Ethereum mainnet nodes

## Phase 2: Storage 🔜

- [ ] RocksDB Rust NIF (`eth_storage`)
- [ ] `EthStorage.Backend` behaviour definition
- [ ] Memory backend (for testing)
- [ ] MPT (Merkle Patricia Trie)
  - [ ] Rust NIF for hashing
  - [ ] Elixir trie structure
  - [ ] `EthStorage.Trie` behaviour
- [ ] Account state store/retrieve
- **Completion criteria**: MPT state root calculation matches ethereum/tests fixtures

## Phase 2.5: EVM 🔜

- [ ] revm Rust NIF
- [ ] `EthEvm.Executor` behaviour definition
- [ ] Host trait implementation (storage integration)
- [ ] Precompile contracts (ecrecover, sha256, ripemd160, identity, modexp, ecadd, ecmul, ecpairing, blake2f)
- **Completion criteria**: Shanghai state tests 90%+ pass rate

## Phase 3.5: Chain

- [ ] Block validation (header, body, state transition)
- [ ] State transition function
- [ ] Block import pipeline
- [ ] Fork choice rule
- **Completion criteria**: Shanghai blockchain tests 90%+ pass rate

## Phase 4: RPC

- [ ] JSON-RPC server (Bandit + Plug)
- [ ] `eth_*` namespace (core methods)
  - [ ] eth_blockNumber, eth_getBalance, eth_getTransactionByHash
  - [ ] eth_call, eth_estimateGas, eth_sendRawTransaction
  - [ ] eth_getBlockByNumber, eth_getBlockByHash
  - [ ] eth_getLogs, eth_getTransactionReceipt
- [ ] Engine API (consensus layer integration)
  - [ ] engine_newPayloadV3
  - [ ] engine_forkchoiceUpdatedV3
  - [ ] engine_getPayloadV3
- [ ] JWT authentication for Engine API
- **Completion criteria**: Hive RPC simulator pass

## Phase 5: Sync & Stabilization

- [ ] Snap sync protocol (eth/snap)
- [ ] Full sync fallback
- [ ] Mainnet synchronization
- [ ] Performance optimization
- [ ] Documentation
- **Completion criteria**: All Hive simulators pass, mainnet sync to latest block
