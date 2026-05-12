#!/usr/bin/env sh
set -eu

DIST_DIR="${1:-${AEGIS_DIST_DIR:-dist}}"

[ -d "$DIST_DIR" ] || { printf 'release verify: missing dist dir: %s\n' "$DIST_DIR" >&2; exit 1; }
[ -s "$DIST_DIR/checksums.txt" ] || { printf 'release verify: missing checksums.txt\n' >&2; exit 1; }
[ -s "$DIST_DIR/release-manifest.json" ] || { printf 'release verify: missing release-manifest.json\n' >&2; exit 1; }
[ -s "$DIST_DIR/sbom.json" ] || { printf 'release verify: missing sbom.json\n' >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIST_DIR" && sha256sum -c checksums.txt)
else
  (cd "$DIST_DIR" && shasum -a 256 -c checksums.txt)
fi

for required in \
  "$DIST_DIR"/aegis-v*-darwin-amd64.tar.gz \
  "$DIST_DIR"/aegis-v*-darwin-arm64.tar.gz \
  "$DIST_DIR"/aegis-v*-linux-amd64.tar.gz \
  "$DIST_DIR"/aegis-v*-linux-arm64.tar.gz \
  "$DIST_DIR"/aegis-v*-windows-amd64.zip \
  "$DIST_DIR"/aegis-edge-v*-linux-amd64.tar.gz \
  "$DIST_DIR"/aegis-edge-v*-linux-arm64.tar.gz
do
  [ -f "$required" ] || { printf 'release verify: missing artifact pattern %s\n' "$required" >&2; exit 1; }
done

grep -q "not real-flight readiness" "$DIST_DIR/release-manifest.json"
grep -q '"signing_status"' "$DIST_DIR/release-manifest.json"
grep -q '"sbom_status"' "$DIST_DIR/release-manifest.json"

printf 'release verify: passed\n'
printf 'Limitations: Aegis Edge release assets are simulation/SITL/customer-evaluation and bench-preparation only; no real hardware, hosted telemetry, certification, detect-and-avoid, or autopilot replacement.\n'
