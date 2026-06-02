#!/usr/bin/env bash
# Cross-platform build script for PvZ2 Gardendless desktop.
# Produces platform-suffixed binaries in dist/.
#
# macOS:  builds universal binary (x86_64 + arm64 lipo'd)
# Linux:  builds for the host architecture (x86_64 or aarch64)
set -euo pipefail

MANIFEST="src-tauri/Cargo.toml"
OUT="dist"

mkdir -p "$OUT"

build_target() {
    local target="$1"
    local label="$2"
    printf "==> Building %s (%s)\n" "$label" "$target"
    cargo build --release --manifest-path "$MANIFEST" --target "$target"
}

copy_binary() {
    local target="$1"
    local suffix="$2"
    cp "src-tauri/target/${target}/release/pvzge" "${OUT}/pvzge-${suffix}"
    printf "    -> %s/pvzge-%s\n" "$OUT" "$suffix"
}

case "$(uname -s)" in
    Darwin)
        printf "==> macOS detected — building universal binary\n\n"

        rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true

        build_target "x86_64-apple-darwin"   "macOS Intel"
        build_target "aarch64-apple-darwin"  "macOS Apple Silicon"

        printf "\n==> Creating universal binary with lipo\n"
        lipo -create \
            "src-tauri/target/x86_64-apple-darwin/release/pvzge" \
            "src-tauri/target/aarch64-apple-darwin/release/pvzge" \
            -output "${OUT}/pvzge-macos-universal"

        printf "    -> %s/pvzge-macos-universal\n" "$OUT"
        ;;

    Linux)
        ARCH="$(uname -m)"
        case "$ARCH" in
            x86_64)
                build_target "x86_64-unknown-linux-gnu" "Linux x86_64"
                copy_binary  "x86_64-unknown-linux-gnu" "linux-x86_64"
                ;;
            aarch64)
                build_target "aarch64-unknown-linux-gnu" "Linux arm64"
                copy_binary  "aarch64-unknown-linux-gnu" "linux-aarch64"
                ;;
            *)
                printf "error: unsupported architecture %s\n" "$ARCH" >&2
                exit 1
                ;;
        esac
        ;;

    *)
        printf "error: unsupported platform %s\n" "$(uname -s)" >&2
        exit 1
        ;;
esac

printf "\n==> Build complete\n"
ls -lh "${OUT}"/pvzge-* 2>/dev/null || true
