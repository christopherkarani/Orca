#!/usr/bin/env bash
# Build both the Zig CLI and the Rust daemon binary.
#
# Usage:
#   ./scripts/build-all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[build-all] Building Zig binary..."
"${SCRIPT_DIR}/zig" build

echo "[build-all] Building Rust daemon binary..."
cd orca-rs
cargo build --release
cd "${REPO_ROOT}"

echo "[build-all] Done."
echo ""
echo "  Zig binary:    zig-out/bin/orca"
echo "  Rust binary:   orca-rs/target/release/orca-daemon"
