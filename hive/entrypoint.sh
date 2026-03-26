#!/bin/bash
# Hive entrypoint for ex_ethclient.
#
# Maps Hive-injected environment variables into the configuration that
# ex_ethclient's Elixir release understands (runtime.exs reads System.get_env).
#
# Reference: https://github.com/ethereum/hive/blob/master/docs/clients.md

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DATA_DIR="/data"
RPC_PORT=8545
ENGINE_PORT=8551
P2P_PORT=30303

# ---------------------------------------------------------------------------
# Map HIVE_* env vars to ex_ethclient env vars
# ---------------------------------------------------------------------------

# Chain / network identity
if [ -n "${HIVE_CHAIN_ID:-}" ]; then
  export ETH_CHAIN_ID="${HIVE_CHAIN_ID}"
fi

if [ -n "${HIVE_NETWORK_ID:-}" ]; then
  export ETH_NETWORK_ID="${HIVE_NETWORK_ID}"
fi

# Data directory
export ETH_DATADIR="${DATA_DIR}"
export DATADIR="${DATA_DIR}/storage"
mkdir -p "${DATADIR}"

# P2P port
export ETH_PORT="${P2P_PORT}"

# RPC
export ETH_RPC_PORT="${RPC_PORT}"
export ETH_ENGINE_PORT="${ENGINE_PORT}"

# Bootnodes — Hive passes a comma-separated list of enode URIs
if [ -n "${HIVE_BOOTNODE:-}" ]; then
  export ETH_BOOTNODES="${HIVE_BOOTNODE}"
fi

# Log level mapping: Hive uses integer levels (0-5), map to Elixir Logger levels
# 0=silent 1=error 2=warn 3=info 4=debug 5=trace
case "${HIVE_LOGLEVEL:-3}" in
  0) export LOG_LEVEL="none"    ;;
  1) export LOG_LEVEL="error"   ;;
  2) export LOG_LEVEL="warning" ;;
  3) export LOG_LEVEL="info"    ;;
  4) export LOG_LEVEL="debug"   ;;
  5) export LOG_LEVEL="debug"   ;;
  *) export LOG_LEVEL="info"    ;;
esac

# Genesis block — Hive may mount a genesis.json at /genesis.json
if [ -f "/genesis.json" ]; then
  export ETH_GENESIS="/genesis.json"
fi

# JWT secret for Engine API — Hive mounts this at /jwt.hex
if [ -f "/jwt.hex" ]; then
  export ETH_JWT_SECRET="/jwt.hex"
elif [ -f "/hive/input/jwt-secret.txt" ]; then
  export ETH_JWT_SECRET="/hive/input/jwt-secret.txt"
fi

# Node type (full / light) — not yet used but exported for future use
if [ -n "${HIVE_NODETYPE:-}" ]; then
  export ETH_NODETYPE="${HIVE_NODETYPE}"
fi

# ---------------------------------------------------------------------------
# Import genesis if provided
# ---------------------------------------------------------------------------
if [ -f "/genesis.json" ]; then
  echo "Hive: genesis.json found, will import at startup"
fi

# ---------------------------------------------------------------------------
# Print configuration summary
# ---------------------------------------------------------------------------
echo "=== ex_ethclient (Hive mode) ==="
echo "Chain ID:    ${HIVE_CHAIN_ID:-not set}"
echo "Network ID:  ${HIVE_NETWORK_ID:-not set}"
echo "P2P port:    ${P2P_PORT}"
echo "RPC port:    ${RPC_PORT}"
echo "Engine port: ${ENGINE_PORT}"
echo "Log level:   ${LOG_LEVEL}"
echo "Data dir:    ${DATA_DIR}"
echo "Bootnodes:   ${HIVE_BOOTNODE:-none}"
echo "================================"

# ---------------------------------------------------------------------------
# Start the release
# ---------------------------------------------------------------------------
exec /opt/ex_ethclient/bin/ex_ethclient start
