#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$DIR/../../../.." && pwd)
BIN=${EDGE_BIN:-"$ROOT/zig-out/bin/edge"}
"$BIN" health scenario run --policy "$DIR/policy.yaml" --scenario "$DIR/scenario.yaml"
