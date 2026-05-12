#!/usr/bin/env bash
set -euo pipefail

VERSION="${AEGIS_EDGE_VERSION:-1.1.0}"
PREFIX="${PREFIX:-${HOME}/.local}"
BIN_DIR="${PREFIX}/bin"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "${OS}:${ARCH}" in
  linux:x86_64) TARGET="linux-amd64" ;;
  linux:aarch64|linux:arm64) TARGET="linux-arm64" ;;
  *) printf 'unsupported Aegis Edge install target: %s/%s\n' "${OS}" "${ARCH}" >&2; exit 64 ;;
esac

ARTIFACT="aegis-edge-v${VERSION}-${TARGET}.tar.gz"
printf 'Selected artifact: %s\n' "${ARTIFACT}"
printf 'Install path: %s/aegis-edge\n' "${BIN_DIR}"
printf 'This script does not configure hardware, services, telemetry, or credentials.\n'

if [ -f "${ARTIFACT}" ]; then
  if [ -f "SHA256SUMS" ]; then
    sha256sum -c --ignore-missing SHA256SUMS
  fi
  package_root="$(tar -tzf "${ARTIFACT}" | sed -n '1{s#/.*##;p;}')"
  if [ -z "${package_root}" ]; then
    printf 'artifact has no package root: %s\n' "${ARTIFACT}" >&2
    exit 67
  fi
  mkdir -p "${PREFIX}" "${BIN_DIR}"
  tar -xzf "${ARTIFACT}" -C "${PREFIX}"
  extracted_bin="${PREFIX}/${package_root}/bin/aegis-edge"
  if [ ! -x "${extracted_bin}" ]; then
    printf 'extracted binary missing or not executable: %s\n' "${extracted_bin}" >&2
    exit 67
  fi
  install -m 0755 "${extracted_bin}" "${BIN_DIR}/aegis-edge"
else
  printf 'artifact not found locally; build or download it first\n' >&2
  exit 66
fi
