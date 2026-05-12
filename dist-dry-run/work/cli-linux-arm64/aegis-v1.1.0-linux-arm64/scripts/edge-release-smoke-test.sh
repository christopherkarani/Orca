#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
AEGIS_EDGE="${AEGIS_EDGE:-$ROOT/zig-out/bin/aegis-edge}"

# Artifact checksum verification is handled by scripts/verify-release.sh before
# extracted-archive smoke tests run.
cd "$ROOT"
[ -x "$AEGIS_EDGE" ] || { printf 'edge release smoke: missing binary at %s\n' "$AEGIS_EDGE" >&2; exit 1; }

"$AEGIS_EDGE" --help >/dev/null
"$AEGIS_EDGE" version >/dev/null
"$AEGIS_EDGE" version --json >/dev/null
"$AEGIS_EDGE" doctor >/dev/null
"$AEGIS_EDGE" redteam --ci >/dev/null
"$AEGIS_EDGE" docs check >/dev/null
"$AEGIS_EDGE" demo run geofence-deny >/dev/null
"$AEGIS_EDGE" proof generate --demo geofence-deny >/dev/null
"$AEGIS_EDGE" safety-case verify --session last >/dev/null
"$AEGIS_EDGE" deployment doctor >/dev/null
"$AEGIS_EDGE" deployment assets >/dev/null
"$AEGIS_EDGE" bench doctor >/dev/null
"$AEGIS_EDGE" health doctor >/dev/null
"$AEGIS_EDGE" data doctor >/dev/null

printf 'edge release smoke passed\n'
printf 'Limitations: simulation/SITL/customer-evaluation and bench-preparation only; no real-flight readiness or certification.\n'
