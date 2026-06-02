#!/usr/bin/env bash
# Fast local verification for policy/CLI/core changes (Zig 0.15.2).
#
# Tiered gate: compile + focused unit tests + quick-install DX matrix.
# Use `./scripts/zig build test` before merge/CI (full plugin/phase suites).
#
# Usage:
#   ./scripts/test-fast.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "[test-fast] Toolchain check (want 0.15.2 from .zigversion)"
./scripts/ensure-zig-toolchain.sh --check

echo "[test-fast] Build orca"
./scripts/zig build

echo "[test-fast] Unit tests (lib + orca_core only)"
./scripts/zig build test-fast

echo "[test-fast] Quick-install / generic-agent policy matrix"
./scripts/quick-install-dx-verify.sh

echo "[test-fast] All fast checks passed."
