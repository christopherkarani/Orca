#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/VERSION")"

detect_os() {
  case "$(uname -s)" in
  Darwin) printf 'darwin' ;;
  Linux) printf 'linux' ;;
  *) printf 'unsupported' ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
  x86_64 | amd64) printf 'amd64' ;;
  arm64 | aarch64) printf 'arm64' ;;
  *) printf 'unsupported' ;;
  esac
}

fail() {
  printf 'install-layout-smoke: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected output to contain: ${needle}"
  fi
}

assert_json_field() {
  local haystack="$1"
  local key="$2"
  local value="$3"
  if ! grep -Eq "\"${key}\"[[:space:]]*:[[:space:]]*\"${value}\"" <<<"${haystack}"; then
    fail "expected JSON field ${key}=${value}"
  fi
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
[[ "${OS}" != "unsupported" ]] || fail "unsupported host OS for smoke test"
[[ "${ARCH}" != "unsupported" ]] || fail "unsupported host architecture for smoke test"

ARTIFACT="${DIST_DIR}/orca-v${VERSION}-${OS}-${ARCH}.tar.gz"
[[ -f "${ARTIFACT}" ]] || fail "missing host artifact: ${ARTIFACT}"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/orca-install-layout.XXXXXX")"
cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT INT TERM

tar -xzf "${ARTIFACT}" -C "${TMP_ROOT}"
STAGE_ROOT="${TMP_ROOT}/orca-v${VERSION}-${OS}-${ARCH}"
ORCA_BIN="${STAGE_ROOT}/bin/orca"
DAEMON_BIN="${STAGE_ROOT}/bin/orca-daemon"
[[ -x "${ORCA_BIN}" ]] || fail "staged orca binary is missing or not executable"
[[ -x "${DAEMON_BIN}" ]] || fail "staged orca-daemon binary is missing or not executable"

TMP_HOME="${TMP_ROOT}/home"
mkdir -p "${TMP_HOME}/workspace"

export HOME="${TMP_HOME}"
export PATH="${STAGE_ROOT}/bin:${PATH}"
export ORCA_RESOURCE_ROOT="${STAGE_ROOT}"

version_output="$("${ORCA_BIN}" version)"
assert_contains "${version_output}" "Version"
assert_contains "${version_output}" "${VERSION}"
assert_contains "${version_output}" "Daemon"

doctor_output="$("${ORCA_BIN}" doctor --verbose)"
assert_contains "${doctor_output}" "daemon health: compatible"
assert_contains "${doctor_output}" "daemon binary:"

"${ORCA_BIN}" packs --help >/dev/null

dangerous_fixture="${REPO_ROOT}/tests/plugin-fixtures/claude/pre_tool_use_command_dangerous.json"
safe_fixture="${REPO_ROOT}/tests/plugin-fixtures/claude/pre_tool_use_command_safe.json"
[[ -f "${dangerous_fixture}" ]] || fail "missing dangerous hook fixture"
[[ -f "${safe_fixture}" ]] || fail "missing safe hook fixture"

dangerous_output="$("${ORCA_BIN}" hook claude PreToolUse <"${dangerous_fixture}")"
assert_json_field "${dangerous_output}" "decision" "block"

mv "${DAEMON_BIN}" "${DAEMON_BIN}.bak"

degraded_version="$("${ORCA_BIN}" version)"
assert_contains "${degraded_version}" "Daemon"
assert_contains "${degraded_version}" "unavailable"

degraded_doctor="$("${ORCA_BIN}" doctor --verbose)"
assert_contains "${degraded_doctor}" "daemon health: unavailable"
assert_contains "${degraded_doctor}" "orca-daemon binary not found"

fail_closed_output="$("${ORCA_BIN}" hook claude PreToolUse <"${safe_fixture}")"
assert_json_field "${fail_closed_output}" "decision" "block"
assert_contains "${fail_closed_output}" "daemon unavailable"

[[ -d "${STAGE_ROOT}/orca-dashboard-ui/dist" ]] || fail "staged release missing orca-dashboard-ui/dist"
[[ -f "${STAGE_ROOT}/orca-dashboard-ui/dist/index.html" ]] || fail "staged dashboard bundle missing index.html"

printf '[install-layout-smoke] passed for %s-%s\n' "${OS}" "${ARCH}"
