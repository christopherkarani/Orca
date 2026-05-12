#!/usr/bin/env sh
set -eu

# Builds the checksum-covered Aegis Edge release archive set.
AEGIS_RELEASE_PRODUCT=edge exec ./scripts/build-release.sh "$@"
