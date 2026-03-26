# General-purpose Dockerfile for ex_ethclient.
# Produces a self-contained OTP release image.
#
# Build:
#   docker build -t ex_ethclient .
#
# Run:
#   docker run -p 8545:8545 -p 8551:8551 -p 30303:30303 -p 30303:30303/udp \
#     -v $(pwd)/data:/data ex_ethclient

# ---------------------------------------------------------------------------
# Stage 1 – Build
# ---------------------------------------------------------------------------
FROM hexpm/elixir:1.18.3-erlang-28.0-debian-bookworm-20250113 AS build

# Install Rust (needed for NIF compilation: ex_keccak, ex_secp256k1)
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates cmake && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --default-toolchain stable && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build

# Cache dependency resolution
COPY mix.exs mix.lock ./
COPY apps/eth_core/mix.exs apps/eth_core/mix.exs
COPY apps/eth_crypto/mix.exs apps/eth_crypto/mix.exs
COPY apps/eth_net/mix.exs apps/eth_net/mix.exs
COPY apps/eth_storage/mix.exs apps/eth_storage/mix.exs
COPY apps/eth_vm/mix.exs apps/eth_vm/mix.exs
COPY apps/eth_chain/mix.exs apps/eth_chain/mix.exs
COPY apps/eth_rpc/mix.exs apps/eth_rpc/mix.exs
COPY apps/eth_dashboard/mix.exs apps/eth_dashboard/mix.exs
COPY config config

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix deps.compile

# Copy all application source
COPY apps apps

RUN mix compile --warnings-as-errors && \
    mix release ex_ethclient

# ---------------------------------------------------------------------------
# Stage 2 – Runtime
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      libstdc++6 openssl libncurses6 locales ca-certificates && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /opt/ex_ethclient

# Copy the built release
COPY --from=build /build/_build/prod/rel/ex_ethclient ./

# Create data directory
RUN mkdir -p /data

ENV ETH_DATADIR=/data \
    DATADIR=/data/storage \
    ETH_PORT=30303 \
    ETH_RPC_PORT=8545 \
    ETH_ENGINE_PORT=8551

# JSON-RPC HTTP, Engine API, P2P TCP+UDP
EXPOSE 8545 8551 30303 30303/udp

CMD ["/opt/ex_ethclient/bin/ex_ethclient", "start"]
