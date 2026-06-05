#!/usr/bin/env bash
# Fast compile-only gates for local iteration (Zig 0.16.0).
#
# Use this while editing Zig sources: compile first, run tests only when needed.
# Always uses pinned ./scripts/zig with incremental compilation and -j1.
#
# Usage:
#   ./scripts/compile-fast.sh              # default: check (CLI only)
#   ./scripts/compile-fast.sh check        # compile orca executable
#   ./scripts/compile-fast.sh test-lib     # compile orca lib test binary (largest test-fast piece)
#   ./scripts/compile-fast.sh test-fast    # compile all test-fast artifacts
#   ./scripts/compile-fast.sh test-lib-run # compile + run lib tests (serial, no parallel hang)
#   ./scripts/compile-fast.sh test-fast-run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ZIG_BUILD=(./scripts/zig build -fincremental -j1 -Dincremental=true)

mode="${1:-check}"
case "${mode}" in
  check)
    echo "[compile-fast] check (orca CLI only)"
    "${ZIG_BUILD[@]}" check
    ;;
  test-lib)
    echo "[compile-fast] compile-test-lib (orca lib tests, no run)"
    "${ZIG_BUILD[@]}" compile-test-lib
    ;;
  test-fast)
    echo "[compile-fast] compile-test-fast (all fast test artifacts, no run)"
    "${ZIG_BUILD[@]}" compile-test-fast
    ;;
  test-lib-run)
    echo "[compile-fast] test-lib (compile + run)"
    "${ZIG_BUILD[@]}" test-lib
    ;;
  test-fast-run)
    echo "[compile-fast] test-fast (compile + run, serial)"
    "${ZIG_BUILD[@]}" test-fast
    ;;
  *)
    echo "usage: $0 [check|test-lib|test-fast|test-lib-run|test-fast-run]" >&2
    exit 2
    ;;
esac

echo "[compile-fast] OK (${mode})"