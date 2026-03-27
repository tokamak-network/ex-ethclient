# EthStorage

Storage layer for the ex_ethclient execution client.

Provides a behaviour-based storage backend with pluggable implementations (in-memory ETS, DETS, RocksDB NIF). Includes Merkle Patricia Trie (MPT), genesis state initialization, state pruning with reference counting, and block/account/receipt storage.

## Key Modules

- `EthStorage.Store` - Primary GenServer coordinating all storage operations
- `EthStorage.Backend` - Storage backend behaviour
- `EthStorage.Backend.Memory` - ETS-based in-memory backend (testing)
- `EthStorage.Backend.DETS` - DETS-based persistent backend
- `EthStorage.Backend.RocksDB` - RocksDB NIF backend (production)
- `EthStorage.MPT.Trie` - Merkle Patricia Trie implementation
- `EthStorage.Pruner` - State pruning with reference counting
- `EthStorage.Genesis` - Genesis block and state initialization
- `EthStorage.AccountRLP` - Account RLP encoding/decoding
