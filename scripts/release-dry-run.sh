#!/usr/bin/env sh
set -eu

DIST_DIR="${ORCA_DIST_DIR:-dist-dry-run}"

# Verifies release archive checksums through scripts/verify-release.sh.
printf 'release dry-run: building artifacts into %s\n' "$DIST_DIR"
ORCA_RELEASE_PRODUCT=host ORCA_DIST_DIR="$DIST_DIR" ./scripts/build-release.sh
ORCA_RELEASE_PRODUCT=host ./scripts/verify-release.sh "$DIST_DIR"
ORCA_DIST_DIR="$DIST_DIR" ./scripts/install-layout-smoke-test.sh

printf 'release dry-run: passed\n'
printf 'Limitations: no real hardware, PX4/ArduPilot SITL opt-in only, no hosted telemetry, no secrets required.\n'
