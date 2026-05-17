#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EDGE_BIN="${EDGE_BIN:-$ROOT/zig-out/bin/edge}"

# Artifact checksum verification is handled by scripts/verify-release.sh before
# extracted-archive smoke tests run.
cd "$ROOT"
[ -x "$EDGE_BIN" ] || { printf 'edge release smoke: missing binary at %s\n' "$EDGE_BIN" >&2; exit 1; }

"$EDGE_BIN" --help >/dev/null
"$EDGE_BIN" version >/dev/null
"$EDGE_BIN" version --json >/dev/null
"$EDGE_BIN" doctor >/dev/null
"$EDGE_BIN" redteam --ci >/dev/null
"$EDGE_BIN" docs check >/dev/null
"$EDGE_BIN" demo run geofence-deny >/dev/null
"$EDGE_BIN" proof generate --demo geofence-deny >/dev/null
"$EDGE_BIN" safety-case verify --session last >/dev/null
"$EDGE_BIN" deployment doctor >/dev/null
"$EDGE_BIN" deployment assets >/dev/null
"$EDGE_BIN" bench doctor >/dev/null
"$EDGE_BIN" health doctor >/dev/null
"$EDGE_BIN" data doctor >/dev/null

printf 'edge release smoke passed\n'
printf 'Limitations: simulation/SITL/customer-evaluation and bench-preparation only; no real-flight readiness or certification.\n'
