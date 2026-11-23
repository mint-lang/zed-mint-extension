#!/usr/bin/env bash
# Builds the extension in containers, so no local Rust or C toolchain is
# needed - only Docker. Nothing is written to the working tree except the
# results, which are what Zed loads:
#
#   extension  ./extension.wasm      (the Rust extension)
#   grammar    ./grammars/mint.wasm  (the Tree-sitter grammar)
#
# Usage: ./build.sh [extension] [grammar]   (both when none is given)
#
# Note: `zed: install dev extension` and `zed: rebuild dev extension` compile
# with a local Rust toolchain and will fail without one. Use this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${RUST_IMAGE:-rust:1-slim}"
TARGET="wasm32-wasip2"

# The wasi-sdk release Zed compiles grammars with, so the result is the same as
# what `zed: rebuild dev extension` would produce.
WASI_SDK_VERSION="25"

# A local Mint checkout to take the grammar from when it has the pinned commit
# (e.g. one that is not pushed yet); otherwise it is fetched from the
# repository in `extension.toml`.
MINT_REPO="${MINT_REPO:-$ROOT/../mint}"

build_extension() {
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
}

# Prints a key of the `[grammars.mint]` table of `extension.toml`.
grammar_setting() {
  awk -v key="$1" '
    /^\[/ { section = $0 }
    section == "[grammars.mint]" && $1 == key {
      sub(/^[^=]*=[ \t]*"/, ""); sub(/".*$/, ""); print; exit
    }
  ' "$ROOT/extension.toml"
}

build_grammar() {
  local repository commit path source sources
  repository="$(grammar_setting repository)"
  commit="$(grammar_setting commit)"
  path="$(grammar_setting path)"

  sources="$(mktemp -d)"
  SOURCES_TO_CLEAN="$sources"

  if git -C "$MINT_REPO" cat-file -e "$commit^{commit}" 2>/dev/null; then
    source="$MINT_REPO"
  else
    source="$sources/repository"
    git init -q --bare "$source"
    git -C "$source" fetch -q --depth 1 "$repository" "$commit"
  fi

  echo "Building the grammar from $source at $commit"
  mkdir "$sources/src"
  git -C "$source" archive "$commit:${path:+$path/}src" | tar -x -C "$sources/src"

  DOCKER_BUILDKIT=1 docker build \
    --build-arg "WASI_SDK_VERSION=$WASI_SDK_VERSION" \
    --target output \
    --output "type=local,dest=$ROOT/grammars" \
    --file - "$sources/src" <<'DOCKERFILE'
# syntax=docker/dockerfile:1
FROM debian:12-slim AS base-amd64
ENV WASI_SDK_ARCH=x86_64

FROM debian:12-slim AS base-arm64
ENV WASI_SDK_ARCH=arm64

FROM base-${TARGETARCH} AS build
ARG WASI_SDK_VERSION
ADD https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_VERSION}.0-${WASI_SDK_ARCH}-linux.tar.gz /wasi-sdk.tar.gz
RUN mkdir /wasi-sdk && tar -xzf /wasi-sdk.tar.gz -C /wasi-sdk --strip-components=1
COPY . /src
# The same command `zed: rebuild dev extension` runs.
RUN /wasi-sdk/bin/clang -fPIC -shared -Os -Wl,--export=tree_sitter_mint \
      -o /mint.wasm -I /src /src/parser.c /src/scanner.c

FROM scratch AS output
COPY --from=build /mint.wasm /mint.wasm
DOCKERFILE

  echo "Built $ROOT/grammars/mint.wasm"
}

# The grammar sources are copied to a temporary directory outside the tree.
SOURCES_TO_CLEAN=""
trap '[ -n "$SOURCES_TO_CLEAN" ] && rm -rf "$SOURCES_TO_CLEAN"' EXIT

targets=("$@")
[ ${#targets[@]} -eq 0 ] && targets=(extension grammar)

for target in "${targets[@]}"; do
  case "$target" in
    extension) build_extension ;;
    grammar) build_grammar ;;
    *) echo "Unknown target: $target (expected extension or grammar)" >&2; exit 1 ;;
  esac
done
