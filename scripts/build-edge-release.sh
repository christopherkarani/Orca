#!/usr/bin/env sh
set -eu

# Builds the checksum-covered Edge release archive set.
ORCA_RELEASE_PRODUCT=edge exec ./scripts/build-release.sh "$@"
