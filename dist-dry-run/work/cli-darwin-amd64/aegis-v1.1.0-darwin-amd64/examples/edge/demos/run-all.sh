#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BIN=${AEGIS_EDGE:-"$ROOT/zig-out/bin/aegis-edge"}
cd "$ROOT"
"$BIN" demo run all
