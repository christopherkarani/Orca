#!/usr/bin/env bash
# Local mirror of the *fast* PR signal (not full matrix / full zig test).
#
#   - Zig: test-fast.sh units (build + monopath units, no quick-install)
#   - Zig shell_engine MVP corpus
#
# Usage:
#   ./scripts/ci-local-fast.sh
#   ./scripts/ci-local-fast.sh --zig-only
#
# Full suite remains: ./scripts/zig build test / ./scripts/verify-pre-merge.sh
# See Agents.md → Verification gates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-rust|--rust-only)
      echo "warning: Rust daemon removed; ignoring $1" >&2
      shift
      ;;
    --zig-only) shift ;;
    -h|--help)
      echo "usage: $0 [--zig-only]" >&2
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

gate_start=$(date +%s)

echo "[ci-local-fast] Zig units (test-fast.sh units)"
./scripts/test-fast.sh units

echo "[ci-local-fast] Zig shell_engine MVP corpus"
./scripts/zig build test-shell-engine

total=$(( $(date +%s) - gate_start ))
echo "[ci-local-fast] OK in ${total}s"
