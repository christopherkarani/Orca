#!/usr/bin/env bash
set -euo pipefail

ARCH="$(uname -m)"
case "${ARCH}" in
  aarch64|arm64) ;;
  *)
    printf 'ARM64 execution unavailable on %s; skipping without pass claim\n' "${ARCH}"
    exit 0
    ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AEGIS_EDGE="${AEGIS_EDGE:-${ROOT}/zig-out/bin/aegis-edge}"

"${AEGIS_EDGE}" --help >/dev/null
"${AEGIS_EDGE}" doctor arm64 >/dev/null
"${AEGIS_EDGE}" deployment check --profile examples/edge/deployment/profiles/packaged-linux-arm64-fake.yaml >/dev/null
"${AEGIS_EDGE}" redteam --ci >/dev/null

printf 'edge arm64 smoke passed\n'
