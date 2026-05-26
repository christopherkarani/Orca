#!/usr/bin/env bash
# Simulates a packaged Orca install layout (no git clone) and verifies plugin wiring.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ORCA_BIN="${REPO_ROOT}/zig-out/bin/orca"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

if [[ ! -x "${ORCA_BIN}" ]]; then
  echo "install-dx-smoke: building orca binary first..." >&2
  (cd "${REPO_ROOT}" && zig build)
fi

assert_json_field() {
  local json="$1"
  local field="$2"
  local expected="$3"
  if command -v jq >/dev/null 2>&1; then
    actual="$(printf '%s' "${json}" | jq -r "${field}")"
    if [[ "${actual}" != "${expected}" ]]; then
      echo "install-dx-smoke: expected ${field}=${expected}, got ${actual}" >&2
      exit 1
    fi
    return 0
  fi
  case "${expected}" in
    true) printf '%s' "${json}" | grep -q "\"${field##*.}\": true" ;;
    false) printf '%s' "${json}" | grep -q "\"${field##*.}\": false" ;;
    *) printf '%s' "${json}" | grep -Fq "\"${field##*.}\": \"${expected}\"" ;;
  esac
}

canonical_path() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/orca-install-dx.XXXXXX")"
cleanup() {
  rm -rf "${TMP_HOME}"
}
trap cleanup EXIT INT TERM

RESOURCE_ROOT="${TMP_HOME}/.local/share/orca/${VERSION}"
BIN_DIR="${TMP_HOME}/.local/bin"
mkdir -p "${RESOURCE_ROOT}" "${BIN_DIR}"
ln -sf "${ORCA_BIN}" "${BIN_DIR}/orca"

for dir in integrations fixtures schemas policies; do
  cp -R "${REPO_ROOT}/${dir}" "${RESOURCE_ROOT}/"
done

export HOME="${TMP_HOME}"
export PATH="${BIN_DIR}:${PATH}"
export ORCA_RESOURCE_ROOT="${RESOURCE_ROOT}"

WORKSPACE="${TMP_HOME}/workspace"
mkdir -p "${WORKSPACE}/.orca" "${WORKSPACE}/nested"
printf 'mode: generic-agent\n' > "${WORKSPACE}/.orca/policy.yaml"
cd "${WORKSPACE}/nested"

echo "[install-dx-smoke] ORCA_RESOURCE_ROOT=${ORCA_RESOURCE_ROOT}"

"${ORCA_BIN}" plugin install hermes --yes
hermes_json="$("${ORCA_BIN}" plugin doctor hermes --json)"
assert_json_field "${hermes_json}" ".hermes_paths.user_manifest_exists" "true"

"${ORCA_BIN}" plugin install codex --yes
codex_json="$("${ORCA_BIN}" plugin doctor codex --json)"
assert_json_field "${codex_json}" ".marketplace.codex_user_plugin" "true"
assert_json_field "${codex_json}" ".workspace_root" "$(canonical_path "${WORKSPACE}")"

"${ORCA_BIN}" plugin install claude --yes
claude_json="$("${ORCA_BIN}" plugin doctor claude --json)"
assert_json_field "${claude_json}" ".marketplace.claude_user_plugin" "true"
assert_json_field "${claude_json}" ".workspace_root" "$(canonical_path "${WORKSPACE}")"

# Reinstall helper should replace stale ORCA_RESOURCE_ROOT export when marker exists
RC_FILE="${TMP_HOME}/.zshrc"
marker="# Orca runtime assets"
CURRENT_LINK="${TMP_HOME}/.local/share/orca/current"
{
  printf '\n%s\n' "${marker}"
  printf 'export ORCA_RESOURCE_ROOT="%s"\n' "${TMP_HOME}/.local/share/orca/old-version"
} >> "${RC_FILE}"
tmp_rc="$(mktemp)"
awk -v marker="${marker}" -v new_line="export ORCA_RESOURCE_ROOT=\"${CURRENT_LINK}\"" '
  $0 == marker { print; print new_line; skip=1; next }
  skip && /^export ORCA_RESOURCE_ROOT=/ { next }
  skip && $0 == "" { skip=0 }
  { print }
' "${RC_FILE}" > "${tmp_rc}"
mv "${tmp_rc}" "${RC_FILE}"
grep -qF "export ORCA_RESOURCE_ROOT=\"${CURRENT_LINK}\"" "${RC_FILE}"
grep -qF "export ORCA_RESOURCE_ROOT=\"${TMP_HOME}/.local/share/orca/old-version\"" "${RC_FILE}" && {
  echo "install-dx-smoke: stale ORCA_RESOURCE_ROOT was not replaced" >&2
  exit 1
}

echo "[install-dx-smoke] passed"
