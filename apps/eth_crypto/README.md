# EthCrypto

Cryptographic primitives for the ex_ethclient execution client.

Wraps Keccak-256 hashing, secp256k1 signature operations, and ECIES encryption used by the Ethereum networking and signing layers.

## Key Modules

- `EthCrypto.Hash` - Keccak-256 hashing (via `ex_keccak` NIF)
- `EthCrypto.Signature` - secp256k1 sign/verify/recover (via `ex_secp256k1` NIF)
- `EthCrypto.ECIES` - Elliptic Curve Integrated Encryption Scheme for RLPx handshake
