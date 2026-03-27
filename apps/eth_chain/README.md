# EthChain

Chain logic and block validation for the ex_ethclient execution client.

Implements block/transaction validation, gas calculation, base fee computation (EIP-1559), fork management, transaction mempool, block execution pipeline, and graceful shutdown. Serves as the orchestration layer connecting storage, EVM, and networking.

## Key Modules

- `EthChain.BlockValidator` - Block header and body validation
- `EthChain.TxValidator` - Transaction validation (signature, nonce, gas, balance)
- `EthChain.BlockPipeline` - End-to-end block processing pipeline
- `EthChain.BlockExecutor` - Block execution with EVM integration
- `EthChain.BaseFee` - EIP-1559 base fee calculation
- `EthChain.Gas` - Intrinsic gas computation
- `EthChain.Fork` - Fork schedule and feature detection
- `EthChain.Config` - Chain configuration (mainnet, Sepolia, Holesky)
- `EthChain.Mempool` - Transaction pool management
- `EthChain.PayloadBuilder` - Block payload construction for Engine API
- `EthChain.ShutdownManager` - Graceful shutdown coordination
- `EthChain.BeaconFetcher` - Beacon chain head block fetching
