#!/usr/bin/env sh
set -eu

# Builds the checksum-covered Orca release archive set.
ORCA_RELEASE_PRODUCT=cli exec ./scripts/build-release.sh "$@"
