#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

fail() {
  printf 'docker-install-layout-smoke: %s\n' "$1" >&2
  exit 1
}

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) fail "unsupported Docker host architecture" ;;
esac

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"

artifact="orca-v${VERSION}-linux-${arch}.tar.gz"
artifact_path="${DIST_DIR}/${artifact}"
checksums="${DIST_DIR}/checksums.txt"
[[ -f "${artifact_path}" ]] || fail "missing Linux artifact: ${artifact_path}"
[[ -f "${checksums}" ]] || fail "missing checksums file: ${checksums}"

expected="$(awk -v name="${artifact}" '$2 == name { print $1 }' "${checksums}")"
[[ -n "${expected}" ]] || fail "checksums file has no entry for ${artifact}"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${artifact_path}" | awk '{ print $1 }')"
else
  actual="$(shasum -a 256 "${artifact_path}" | awk '{ print $1 }')"
fi
[[ "${actual}" == "${expected}" ]] || fail "artifact checksum mismatch"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/orca-docker-smoke.XXXXXX")"
image="orca-install-layout-smoke:${VERSION}-${arch}-$$"
cleanup() {
  docker image rm -f "${image}" >/dev/null 2>&1 || true
  rm -rf "${tmp_root}"
}
trap cleanup EXIT INT TERM

tar -xzf "${artifact_path}" -C "${tmp_root}"
mv "${tmp_root}/orca-v${VERSION}-linux-${arch}" "${tmp_root}/orca"
cp "${REPO_ROOT}/packaging/docker/Dockerfile" "${tmp_root}/Dockerfile"

docker build --pull=false -t "${image}" "${tmp_root}" >/dev/null

version_output="$(docker run --rm "${image}" version)"
[[ "${version_output}" == *"orca ${VERSION}"* ]] || fail "container version output is incorrect"
run_output="$(docker run --rm --entrypoint sh "${image}" -ec '
  mkdir -p "$HOME/workspace"
  cd "$HOME/workspace"
  orca init --preset generic-agent >/dev/null
  orca policy check .orca/policy.yaml >/dev/null
  orca run -- echo docker-smoke-ok
')"
[[ "${run_output}" == *"docker-smoke-ok"* ]] || fail "container could not protect and run a command"

printf '[docker-install-layout-smoke] passed for linux-%s\n' "${arch}"
