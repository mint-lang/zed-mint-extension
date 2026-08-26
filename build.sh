#!/usr/bin/env bash
# Builds the extension's WASM component in a container, so no local Rust
# toolchain is needed - only Docker. Nothing is written to the working tree
# except the resulting ./extension.wasm, which is what Zed loads; the cargo
# registry and target directory live in Docker's build cache.
#
# Note: `zed: install dev extension` and `zed: rebuild dev extension` compile
# with a local Rust toolchain and will fail without one. Use this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${RUST_IMAGE:-rust:1-slim}"
TARGET="wasm32-wasip2"

DOCKER_BUILDKIT=1 docker build \
  --build-arg "IMAGE=$IMAGE" \
  --build-arg "TARGET=$TARGET" \
  --target output \
  --output "type=local,dest=$ROOT" \
  --file - "$ROOT" <<'DOCKERFILE'
# syntax=docker/dockerfile:1
ARG IMAGE=rust:1-slim
FROM ${IMAGE} AS build
ARG TARGET=wasm32-wasip2
RUN rustup target add "$TARGET"
WORKDIR /extension
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/extension/target,sharing=locked \
    cargo build --release --target "$TARGET" \
    && cp "target/$TARGET/release/zed_mint.wasm" /extension.wasm

FROM scratch AS output
COPY --from=build /extension.wasm /extension.wasm
DOCKERFILE

echo "Built $ROOT/extension.wasm"
