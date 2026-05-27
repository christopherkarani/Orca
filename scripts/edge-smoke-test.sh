#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE_BIN="${EDGE_BIN:-${ROOT}/zig-out/bin/edge}"
cd "${ROOT}"

"${EDGE_BIN}" --help >/dev/null
"${EDGE_BIN}" doctor >/dev/null
"${EDGE_BIN}" deployment doctor >/dev/null
"${EDGE_BIN}" deployment assets >/dev/null
"${EDGE_BIN}" redteam --ci >/dev/null
"${EDGE_BIN}" safety-case generate --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml >/dev/null
"${EDGE_BIN}" mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml >/dev/null
"${EDGE_BIN}" px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml >/dev/null
"${EDGE_BIN}" ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml >/dev/null
"${EDGE_BIN}" bench report --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml >/dev/null

printf 'edge smoke passed\n'
