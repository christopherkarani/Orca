#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE_BIN="${EDGE_BIN:-${ROOT}/zig-out/bin/edge}"
cd "${ROOT}"

"${EDGE_BIN}" deployment package-info --arch linux-amd64 >/dev/null
"${EDGE_BIN}" deployment package-info --arch linux-arm64 >/dev/null
"${EDGE_BIN}" deployment check --profile examples/edge/deployment/profiles/packaged-linux-arm64-fake.yaml >/dev/null
"${EDGE_BIN}" deployment assets >/dev/null

printf 'edge package smoke passed\n'
