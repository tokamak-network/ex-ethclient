# Hive Integration Testing for ex_ethclient

[Hive](https://github.com/ethereum/hive) is Ethereum's integration testing framework. It spins up execution clients inside Docker containers and runs protocol-level test suites against them.

## Prerequisites

- Docker installed and running
- Go 1.21+ (to build Hive)
- A clone of the Hive repository

## Setup

### 1. Clone Hive

```bash
git clone https://github.com/ethereum/hive.git
cd hive
```

### 2. Register ex_ethclient as a client

Symlink or copy the client definition into Hive's clients directory:

```bash
ln -s /path/to/ex_ethclient/hive clients/ex_ethclient
```

Hive expects the following structure inside `clients/ex_ethclient/`:

```
clients/ex_ethclient/
  Dockerfile      # Multi-stage build for the client
  hive.yaml       # Client metadata (name, version, roles)
  entrypoint.sh   # Startup script that maps Hive env vars
```

### 3. Build Hive

```bash
go build -o ./hive ./cmd/hive
```

## Running Tests

### Smoke test (verify the client builds and starts)

```bash
./hive --client ex_ethclient --sim ethereum/rpc
```

### JSON-RPC conformance

```bash
./hive --client ex_ethclient --sim ethereum/rpc --sim.limit "/"
```

### Engine API tests

```bash
./hive --client ex_ethclient --sim ethereum/engine
```

### Sync tests

```bash
./hive --client ex_ethclient --sim ethereum/sync
```

### Run all eth1 simulators

```bash
./hive --client ex_ethclient --sim "ethereum/*"
```

## Environment Variables

Hive injects these environment variables into the container:

| Variable | Description | Default |
|----------|-------------|---------|
| `HIVE_CHAIN_ID` | Chain ID for the test network | - |
| `HIVE_NETWORK_ID` | Network ID | - |
| `HIVE_BOOTNODE` | Comma-separated enode URIs | - |
| `HIVE_LOGLEVEL` | Log verbosity (0=silent, 5=trace) | 3 |
| `HIVE_NODETYPE` | Node type: full or light | full |

Hive also mounts files:

| Path | Description |
|------|-------------|
| `/genesis.json` | Genesis block definition |
| `/jwt.hex` | JWT secret for Engine API authentication |

## Ports

The container exposes:

| Port | Protocol | Service |
|------|----------|---------|
| 8545 | TCP | JSON-RPC HTTP |
| 8551 | TCP | Engine API (JWT auth) |
| 30303 | TCP+UDP | P2P (devp2p) |

## Troubleshooting

### Build fails on NIF compilation

The Dockerfile installs Rust stable for NIF dependencies (ex_keccak, ex_secp256k1). If compilation fails, check that the Rust toolchain version in the build stage is compatible.

### Client starts but tests fail

Check the Hive test logs at `workspace/logs/`. Common issues:

- Genesis import not yet implemented: ex_ethclient needs to parse `/genesis.json` and initialize state
- Missing RPC methods: some Hive tests require methods not yet implemented
- Engine API: requires JWT authentication to be correctly wired up

### Viewing logs

Hive stores container logs under its workspace directory:

```bash
ls workspace/logs/
```

Or view live logs during a test run via Docker:

```bash
docker logs -f <container_id>
```

## Current Limitations

ex_ethclient is under active development. The following features affect Hive compatibility:

- Genesis JSON import is not yet implemented
- Snap sync is not yet available (Phase 5)
- Some JSON-RPC methods return stub responses
- Engine API methods need full integration with chain/storage
