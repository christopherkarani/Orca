#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
AEGIS_BIN="$ROOT/zig-out/bin/aegis"

cd "$ROOT"
zig build

if [ ! -x "$AEGIS_BIN" ]; then
  printf 'v1 smoke: missing binary at %s\n' "$AEGIS_BIN" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aegis-v1-smoke.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

(
  cd "$TMP_DIR"
  "$AEGIS_BIN" version
  "$AEGIS_BIN" version --json
  "$AEGIS_BIN" doctor
  "$AEGIS_BIN" init --preset generic-agent --force
  "$AEGIS_BIN" policy check .aegis/policy.yaml
  "$AEGIS_BIN" run -- echo hello
  "$AEGIS_BIN" replay --session last --verify
)

"$AEGIS_BIN" redteam --ci

printf 'v1 smoke: passed\n'
