#!/usr/bin/env sh
set -eu

HOST="${1:-}"
SCOPE="${2:-project}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <opencode|openclaw|hermes|codex|claude> [project|global]" >&2
  exit 2
fi

case "$HOST" in
  opencode|openclaw|hermes|hermess|codex|claude) ;;
  *)
    echo "unsupported host: $HOST (expected opencode|openclaw|hermes|codex|claude)" >&2
    exit 2
    ;;
esac

case "$SCOPE" in
  project|global) ;;
  *)
    echo "unsupported scope: $SCOPE (expected project|global)" >&2
    exit 2
    ;;
esac

ORCA_BIN="${ORCA_BIN:-orca}"
if ! command -v "$ORCA_BIN" >/dev/null 2>&1; then
  "${REPO_ROOT}/scripts/install.sh"
  INSTALL_DIR="${ORCA_INSTALL_DIR:-${ORCA_INSTALL_DIR:-${HOME}/.local/bin}}"
  ORCA_BIN="${INSTALL_DIR}/orca"
fi

if [ ! -x "$ORCA_BIN" ] && ! command -v "$ORCA_BIN" >/dev/null 2>&1; then
  echo "orca binary not found after install attempt" >&2
  exit 1
fi

if [ "$HOST" = "hermess" ]; then
  HOST="hermes"
fi

if [ "$HOST" = "opencode" ]; then
  "$ORCA_BIN" plugin install opencode --scope "$SCOPE" --yes
elif [ "$HOST" = "openclaw" ]; then
  "$ORCA_BIN" plugin install openclaw --yes
else
  "$ORCA_BIN" plugin install "$HOST" --yes
fi

"$ORCA_BIN" plugin doctor "$HOST"
