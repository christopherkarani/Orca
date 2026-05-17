#!/usr/bin/env sh
set -eu

DIST_DIR="${ORCA_DIST_DIR:-dist-dry-run}"

# Verifies release archive checksums through scripts/verify-release.sh.
printf 'release dry-run: building artifacts into %s\n' "$DIST_DIR"
ORCA_DIST_DIR="$DIST_DIR" ./scripts/build-release.sh
./scripts/verify-release.sh "$DIST_DIR"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/orca-release-dry-run.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

edge_artifact="$(ls "$DIST_DIR"/edge-v*-linux-amd64.tar.gz 2>/dev/null | head -n 1 || true)"
if [ -n "$edge_artifact" ]; then
  tar -xzf "$edge_artifact" -C "$tmp_dir"
  edge_bin="$(find "$tmp_dir" -type f -path '*/bin/edge' -perm -111 | head -n 1)"
  [ -n "$edge_bin" ] || { printf 'release dry-run: extracted Edge binary missing\n' >&2; exit 1; }
  [ -f "$(dirname "$edge_bin")/../schemas/edge-policy-v1.json" ] || { printf 'release dry-run: extracted Edge schema missing\n' >&2; exit 1; }
  [ -d "$(dirname "$edge_bin")/../examples/edge" ] || { printf 'release dry-run: extracted Edge examples missing\n' >&2; exit 1; }
  if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
    "$edge_bin" version >/dev/null
  else
    printf 'release dry-run: skipped extracted Linux Edge binary execution on non-linux-amd64 host\n'
  fi
fi

printf 'release dry-run: passed\n'
printf 'Limitations: no real hardware, PX4/ArduPilot SITL opt-in only, no hosted telemetry, no secrets required.\n'
