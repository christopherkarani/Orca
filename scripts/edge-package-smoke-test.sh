#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AEGIS_EDGE="${AEGIS_EDGE:-${ROOT}/zig-out/bin/aegis-edge}"
cd "${ROOT}"

"${AEGIS_EDGE}" deployment package-info --arch linux-amd64 >/dev/null
"${AEGIS_EDGE}" deployment package-info --arch linux-arm64 >/dev/null
"${AEGIS_EDGE}" deployment check --profile examples/edge/deployment/profiles/packaged-linux-arm64-fake.yaml >/dev/null
"${AEGIS_EDGE}" deployment assets >/dev/null

printf 'edge package smoke passed\n'
