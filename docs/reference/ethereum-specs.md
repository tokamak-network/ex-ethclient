# Ethereum Specifications Reference

## Implemented EIPs

| EIP | Name | App | Status |
|-----|------|-----|--------|
| EIP-2 | Homestead Hard-fork Changes | eth_core | Done |
| EIP-155 | Simple Replay Attack Protection | eth_core | Done |
| EIP-1559 | Fee Market Change | eth_core | Done |
| EIP-2718 | Typed Transaction Envelope | eth_core | Done |
| EIP-2930 | Access List Transaction | eth_core | Done |
| EIP-4844 | Blob Transactions | eth_core | Done |
| EIP-7702 | Set EOA Account Code | eth_core | Done |

## Transaction Type Formats

### Type 0 (Legacy)
```
rlp([nonce, gasPrice, gasLimit, to, value, data, v, r, s])
```
- `v` = recovery_id + 27 (pre-EIP-155) or recovery_id + chain_id * 2 + 35 (EIP-155)
- EIP-2: `s` must be in lower half of curve order

### Type 1 (EIP-2930 — Access List)
```
0x01 || rlp([chainId, nonce, gasPrice, gasLimit, to, value, data, accessList, signatureYParity, signatureR, signatureS])
```
- `accessList`: list of `[address, [storageKeys...]]` tuples
- Signing hash: `keccak256(0x01 || rlp([chainId, nonce, gasPrice, gasLimit, to, value, data, accessList]))`

### Type 2 (EIP-1559 — Fee Market)
```
0x02 || rlp([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, signatureYParity, signatureR, signatureS])
```
- Effective gas price: `min(maxFeePerGas, baseFeePerGas + maxPriorityFeePerGas)`

### Type 3 (EIP-4844 — Blob)
```
0x03 || rlp([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, maxFeePerBlobGas, blobVersionedHashes, signatureYParity, signatureR, signatureS])
```
- `blobVersionedHashes`: list of 32-byte hashes, each starting with `0x01` version byte
- `maxFeePerBlobGas`: separate fee market for blob data
- Network wrapper adds: `blobs`, `commitments`, `proofs`

### Type 4 (EIP-7702 — Set EOA Account Code)
```
0x04 || rlp([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, authorizationList, signatureYParity, signatureR, signatureS])
```
- `authorizationList`: list of `[chainId, address, nonce, yParity, r, s]` tuples
- Authorization signing: `keccak256(0x05 || rlp([chainId, address, nonce]))`

## Protocol Constants

### RLPx
- Protocol version: 5
- Frame size: 16MB max
- Snappy compression: enabled for messages > 256 bytes
- Key derivation: keccak256 produces 32-byte keys for AES-256-CTR
- ECIES: secp256k1 ECDH + AES-128-CTR + HMAC-SHA-256

### DiscV4
- Packet types: ping(1), pong(2), findnode(3), neighbours(4), enrRequest(5), enrResponse(6)
- Expiration timeout: 20 seconds
- Bucket size (k): 16
- Concurrent lookups (alpha): 3
- Max packet size: 1280 bytes

### eth/68 Protocol
- Message types: Status(0x00), NewBlockHashes(0x01), Transactions(0x02), GetBlockHeaders(0x03), BlockHeaders(0x04), GetBlockBodies(0x05), BlockBodies(0x06), NewBlock(0x07), NewPooledTransactionHashes(0x08), GetPooledTransactions(0x09), PooledTransactions(0x0a), GetReceipts(0x0f), Receipts(0x10)
- Status message includes: version, networkId, td, bestHash, genesisHash, forkId

### Chain IDs
| Network | Chain ID |
|---------|----------|
| Mainnet | 1 |
| Sepolia | 11155111 |
| Holesky | 17000 |

## Key Links
- Yellow Paper: https://ethereum.github.io/yellowpaper/
- Execution Specs: https://github.com/ethereum/execution-specs
- Consensus Specs: https://github.com/ethereum/consensus-specs
- EIPs: https://eips.ethereum.org/
- ethrex: https://github.com/lambdaclass/ethrex
- revm: https://github.com/bluealloy/revm
