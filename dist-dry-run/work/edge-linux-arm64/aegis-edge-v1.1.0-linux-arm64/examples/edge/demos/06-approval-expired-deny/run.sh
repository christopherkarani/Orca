#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../../../.." && pwd)
BIN=${AEGIS_EDGE:-"$ROOT/zig-out/bin/aegis-edge"}
"$BIN" redteam --fixture approval-expired-denied
