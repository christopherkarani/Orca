#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${AEGIS_EDGE:-"$ROOT/zig-out/bin/aegis-edge"}
cd "$ROOT"
printf '%s\n' "Aegis Edge customer-proof demo: fake/SITL/bench-preparation only."
"$BIN" demo run all
