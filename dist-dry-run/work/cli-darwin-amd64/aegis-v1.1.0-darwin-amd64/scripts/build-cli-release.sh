#!/usr/bin/env sh
set -eu

# Builds the checksum-covered Aegis CLI release archive set.
AEGIS_RELEASE_PRODUCT=cli exec ./scripts/build-release.sh "$@"
