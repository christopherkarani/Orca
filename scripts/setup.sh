#!/bin/sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"${SCRIPT_DIR}/install.sh"
INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/bin}"
"${INSTALL_DIR}/orca" setup --auto
