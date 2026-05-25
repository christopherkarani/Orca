#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/bin}"

resolve_orca_bin() {
  if command -v orca >/dev/null 2>&1; then
    command -v orca
    return 0
  fi
  if [ -x "${REPO_ROOT}/zig-out/bin/orca" ]; then
    printf '%s\n' "${REPO_ROOT}/zig-out/bin/orca"
    return 0
  fi
  if [ -x "${INSTALL_DIR}/orca" ]; then
    printf '%s\n' "${INSTALL_DIR}/orca"
    return 0
  fi
  return 1
}

ORCA_BIN="$(resolve_orca_bin)" || {
  "${SCRIPT_DIR}/install.sh"
  ORCA_BIN="${INSTALL_DIR}/orca"
}

"${ORCA_BIN}" setup --auto
