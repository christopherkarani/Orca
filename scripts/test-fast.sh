#!/usr/bin/env bash
# Fast local verification for policy/CLI/core changes (Zig 0.16.0).
#
# Modes (narrowest first):
#   compile  — toolchain check + build CLI + compile test-fast artifacts (no run)
#   units    — compile mode + run test-fast unit binaries (lib + orca_core)
#   full     — units + quick-install / generic-agent policy matrix (default)
#
# Usage:
#   ./scripts/test-fast.sh              # full (default)
#   ./scripts/test-fast.sh full
#   ./scripts/test-fast.sh units
#   ./scripts/test-fast.sh compile
#   ORCA_TEST_FAST=units ./scripts/test-fast.sh
#
# Prefer ./scripts/compile-fast.sh check for pure compile iteration.
# Use ./scripts/zig build test or ./scripts/verify-pre-merge.sh before merge/CI.
# See Agents.md → "Verification gates".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

mode="${1:-${ORCA_TEST_FAST:-full}}"
case "${mode}" in
  full|units|compile) ;;
  *)
    echo "usage: $0 [compile|units|full]" >&2
    echo "  or: ORCA_TEST_FAST=compile|units|full $0" >&2
    exit 2
    ;;
esac

step_start=0
step_begin() {
  step_start=$(date +%s)
  echo "[test-fast] $*"
}
step_end() {
  local label="$1"
  local elapsed=$(( $(date +%s) - step_start ))
  echo "[test-fast] ${label} done in ${elapsed}s"
}

gate_start=$(date +%s)
echo "[test-fast] mode=${mode}"

step_begin "Toolchain check (want 0.16.0 from .zigversion)"
./scripts/ensure-zig-toolchain.sh --check
step_end "toolchain"

step_begin "Build orca CLI"
./scripts/zig build
step_end "build"

if [[ "${mode}" == "compile" ]]; then
  step_begin "Compile test-fast artifacts (no run)"
  ./scripts/zig build compile-test-fast
  step_end "compile-test-fast"
  total=$(( $(date +%s) - gate_start ))
  echo "[test-fast] Compile-only gate passed in ${total}s."
  exit 0
fi

step_begin "Unit tests (lib + orca_core via test-fast)"
./scripts/zig build test-fast
step_end "units"

if [[ "${mode}" == "units" ]]; then
  total=$(( $(date +%s) - gate_start ))
  echo "[test-fast] Units gate passed in ${total}s."
  exit 0
fi

step_begin "Quick-install / generic-agent policy matrix"
./scripts/quick-install-dx-verify.sh
step_end "quick-install"

total=$(( $(date +%s) - gate_start ))
echo "[test-fast] All full fast checks passed in ${total}s."
