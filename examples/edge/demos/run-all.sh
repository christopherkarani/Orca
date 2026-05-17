#!/usr/bin/env sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
BIN=${EDGE_BIN:-"$ROOT/zig-out/bin/edge"}
cd "$ROOT"
"$BIN" demo run all
