#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORCA_BIN="${REPO_ROOT}/zig-out/bin/orca"

fail() {
  printf 'uninstall-first-user-regression: %s\n' "$1" >&2
  exit 1
}

(cd "${REPO_ROOT}" && ./scripts/zig build)

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/orca-uninstall-first-user.XXXXXX")"
cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT INT TERM

prepare_install() {
  local root="$1"
  mkdir -p "${root}/home/custom/bin" \
    "${root}/home/custom/share/orca/1.2.0/fixtures" \
    "${root}/home/custom/share/orca/1.2.0/integrations" \
    "${root}/home/custom/share/orca/1.2.0/schemas" \
    "${root}/home/custom/share/orca/1.2.0/policies" \
    "${root}/home/.config/orca" \
    "${root}/workspace/.orca"
  cp "${ORCA_BIN}" "${root}/home/custom/bin/orca"
  printf '#!/bin/sh\nexit 0\n' > "${root}/home/custom/bin/orca-daemon"
  chmod +x "${root}/home/custom/bin/orca-daemon"
  printf 'orca-runtime-v1\nversion=1.2.0\n' > "${root}/home/custom/share/orca/1.2.0/.orca-installation"
  ln -s "${root}/home/custom/share/orca/1.2.0" "${root}/home/custom/share/orca/current"
  printf 'user config\n' > "${root}/home/.config/orca/config.toml"
  printf 'workspace policy\n' > "${root}/workspace/.orca/policy.yaml"
  cat > "${root}/home/.profile" <<EOF
export KEEP_ME=1
# Added by Orca installer
export PATH="${root}/home/custom/bin:\$PATH"
# Orca runtime assets
export ORCA_RESOURCE_ROOT="${root}/home/custom/share/orca/current"
export ALSO_KEEP_ME=1
EOF
}

keep_root="${tmp_root}/keep-config"
prepare_install "${keep_root}"
(
  cd "${keep_root}/workspace"
  HOME="${keep_root}/home" \
  XDG_CONFIG_HOME="${keep_root}/home/.config" \
  ORCA_RESOURCE_ROOT="${keep_root}/home/custom/share/orca/current" \
  PATH=/usr/bin:/bin \
  "${keep_root}/home/custom/bin/orca" uninstall --yes --keep-config >"${keep_root}/uninstall.log"
)

[[ ! -e "${keep_root}/home/custom/bin/orca" ]] || fail "--keep-config left the CLI binary"
if [[ -e "${keep_root}/home/custom/bin/orca-daemon" ]]; then
  cat "${keep_root}/uninstall.log" >&2
  fail "--keep-config left orca-daemon"
fi
[[ ! -e "${keep_root}/home/custom/share/orca/current" ]] || fail "--keep-config left the current runtime link"
[[ ! -e "${keep_root}/home/custom/share/orca/1.2.0" ]] || fail "--keep-config left runtime assets"
[[ -f "${keep_root}/home/.config/orca/config.toml" ]] || fail "--keep-config removed user config"
[[ -f "${keep_root}/workspace/.orca/policy.yaml" ]] || fail "uninstall removed workspace .orca"
grep -qF 'export KEEP_ME=1' "${keep_root}/home/.profile" || fail "uninstall removed unrelated profile content"
grep -qF 'export ALSO_KEEP_ME=1' "${keep_root}/home/.profile" || fail "uninstall removed unrelated profile content"
! grep -qF '# Added by Orca installer' "${keep_root}/home/.profile" || fail "uninstall left PATH marker"
! grep -qF '# Orca runtime assets' "${keep_root}/home/.profile" || fail "uninstall left runtime marker"

plugins_root="${tmp_root}/plugins-only"
prepare_install "${plugins_root}"
(
  cd "${plugins_root}/workspace"
  HOME="${plugins_root}/home" \
  XDG_CONFIG_HOME="${plugins_root}/home/.config" \
  ORCA_RESOURCE_ROOT="${plugins_root}/home/custom/share/orca/current" \
  PATH=/usr/bin:/bin \
  "${plugins_root}/home/custom/bin/orca" uninstall --yes --plugins-only >/dev/null
)

[[ -x "${plugins_root}/home/custom/bin/orca" ]] || fail "--plugins-only removed the CLI binary"
[[ -x "${plugins_root}/home/custom/bin/orca-daemon" ]] || fail "--plugins-only removed orca-daemon"
[[ -e "${plugins_root}/home/custom/share/orca/current" ]] || fail "--plugins-only removed runtime assets"
grep -qF '# Added by Orca installer' "${plugins_root}/home/.profile" || fail "--plugins-only changed profile activation"

printf '[uninstall-first-user-regression] passed\n'
