#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AEGIS_EDGE="${AEGIS_EDGE:-${ROOT}/zig-out/bin/aegis-edge}"

"${AEGIS_EDGE}" --help >/dev/null
"${AEGIS_EDGE}" doctor >/dev/null
"${AEGIS_EDGE}" deployment doctor >/dev/null
"${AEGIS_EDGE}" deployment assets >/dev/null
"${AEGIS_EDGE}" redteam --ci >/dev/null
"${AEGIS_EDGE}" safety-case generate --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml >/dev/null
"${AEGIS_EDGE}" mavlink simulate --policy examples/edge/mavlink/policies/geofence-mavlink-basic.yaml --scenario examples/edge/mavlink/scenarios/geofence-deny.yaml >/dev/null
"${AEGIS_EDGE}" px4 scenario run --policy examples/edge/px4/policies/px4-geofence-basic.yaml --scenario examples/edge/px4/scenarios/waypoint-outside-geofence-deny.yaml >/dev/null
"${AEGIS_EDGE}" ardupilot scenario run --policy examples/edge/ardupilot/policies/ardupilot-geofence-basic.yaml --scenario examples/edge/ardupilot/scenarios/waypoint-outside-geofence-deny.yaml >/dev/null
"${AEGIS_EDGE}" bench report --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml >/dev/null

printf 'edge smoke passed\n'
