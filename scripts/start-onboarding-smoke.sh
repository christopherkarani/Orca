#!/usr/bin/env bash
# Manual/staged smoke for `orca start` using an isolated HOME.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SMOKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/orca-start-smoke.XXXXXX")"
cleanup() {
    rm -rf "$SMOKE_HOME"
}
trap cleanup EXIT

export HOME="$SMOKE_HOME"
export ORCA_RESOURCE_ROOT="${ORCA_RESOURCE_ROOT:-$ROOT}"

"$ROOT/scripts/zig" build
ORCA="$ROOT/zig-out/bin/orca"

echo "== Fresh environment: orca start (firewall) =="
"$ORCA" start --auto --protection firewall --skip-verify

echo "== Idempotent second run =="
"$ORCA" start --auto --protection firewall --skip-verify

echo "== doctor =="
"$ORCA" doctor

echo "== version =="
"$ORCA" version

echo "orca start smoke completed in $SMOKE_HOME"
