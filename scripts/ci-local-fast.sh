#!/usr/bin/env bash
# Local mirror of the *fast* PR signal (not full matrix / full zig test).
#
# Matches the intent of the lightweight CI zig job:
#   - Zig: test-fast.sh units (build + monopath units, no quick-install)
#   - Rust: cargo test --lib (when orca-rs is dirty or --with-rust)
#
# Usage:
#   ./scripts/ci-local-fast.sh
#   ./scripts/ci-local-fast.sh --with-rust
#   ./scripts/ci-local-fast.sh --zig-only
#   ./scripts/ci-local-fast.sh --rust-only
#
# Full suite remains: ./scripts/zig build test / ./scripts/verify-pre-merge.sh
# See Agents.md → Verification gates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

with_rust=0
zig_only=0
rust_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-rust) with_rust=1; shift ;;
    --zig-only) zig_only=1; shift ;;
    --rust-only) rust_only=1; shift ;;
    -h|--help)
      echo "usage: $0 [--with-rust|--zig-only|--rust-only]" >&2
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${zig_only}" -eq 1 && "${rust_only}" -eq 1 ]]; then
  echo "error: --zig-only and --rust-only are mutually exclusive" >&2
  exit 2
fi

# Auto-include rust when dirty unless zig-only.
if [[ "${with_rust}" -eq 0 && "${zig_only}" -eq 0 && "${rust_only}" -eq 0 ]]; then
  if git status --porcelain 2>/dev/null | awk '{print $NF}' | grep -q '^orca-rs/'; then
    with_rust=1
  fi
fi

gate_start=$(date +%s)

if [[ "${rust_only}" -eq 0 ]]; then
  echo "[ci-local-fast] Zig units (test-fast.sh units)"
  ./scripts/test-fast.sh units
fi

if [[ "${rust_only}" -eq 1 || "${with_rust}" -eq 1 ]]; then
  echo "[ci-local-fast] Rust cargo test --lib"
  (cd orca-rs && cargo test --lib)
fi

total=$(( $(date +%s) - gate_start ))
echo "[ci-local-fast] OK in ${total}s"
