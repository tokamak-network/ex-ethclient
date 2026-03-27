# EthCore

Core Ethereum types and encoding for the ex_ethclient execution client.

Provides fundamental data structures (`Address`, `Hash`, `Block`, `BlockHeader`, `Transaction`, `Account`, `Receipt`, `Log`, `Withdrawal`, `Authorization`, `Bloom`) along with RLP encoding/decoding and transaction signing (EIP-155, EIP-2930, EIP-1559, EIP-4844, EIP-7702).

## Key Modules

- `EthCore.Types.Address` - 20-byte Ethereum address with EIP-55 checksum support
- `EthCore.Types.Hash` - 32-byte Keccak-256 hash
- `EthCore.Types.Transaction` - All transaction types (Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702)
- `EthCore.Types.Block` / `EthCore.Types.BlockHeader` - Block and header structures
- `EthCore.RLP` - RLP encoding/decoding for all Ethereum types
- `EthCore.Transaction.Signer` - Transaction signing and sender recovery
