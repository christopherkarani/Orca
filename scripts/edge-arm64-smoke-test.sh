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
EDGE_BIN="${EDGE_BIN:-${ROOT}/zig-out/bin/edge}"
cd "${ROOT}"

"${EDGE_BIN}" --help >/dev/null
"${EDGE_BIN}" doctor arm64 >/dev/null
"${EDGE_BIN}" deployment check --profile examples/edge/deployment/profiles/packaged-linux-arm64-fake.yaml >/dev/null
"${EDGE_BIN}" redteam --ci >/dev/null

printf 'edge arm64 smoke passed\n'
