#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ORCA_BIN="$ROOT/zig-out/bin/orca"

cd "$ROOT"
zig build

if [ ! -x "$ORCA_BIN" ]; then
  printf 'v1 smoke: missing binary at %s\n' "$ORCA_BIN" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/orca-v1-smoke.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

(
  cd "$TMP_DIR"
  "$ORCA_BIN" version
  "$ORCA_BIN" version --json
  "$ORCA_BIN" doctor
  "$ORCA_BIN" init --preset generic-agent --force
  "$ORCA_BIN" policy check .orca/policy.yaml
  "$ORCA_BIN" run -- echo hello
  "$ORCA_BIN" replay --session last --verify
)

"$ORCA_BIN" redteam --ci

printf 'v1 smoke: passed\n'
