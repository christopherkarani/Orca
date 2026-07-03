#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${1:-${ORCA_LINUX_ARTIFACT_DIR:-${REPO_ROOT}/dist/docker-linux-artifacts}}"
VERSION="${ORCA_VERSION:-$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")}"
COMMIT="${ORCA_COMMIT:-$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)}"
BUILD_DATE="${ORCA_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

command -v docker >/dev/null 2>&1 || {
  echo "build-linux-release-docker: docker is required" >&2
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "build-linux-release-docker: docker daemon is unavailable" >&2
  exit 1
}

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

for arch in amd64 arm64; do
  echo "Building linux-${arch} Orca binaries with Docker"
  docker buildx build \
    --platform "linux/${arch}" \
    --build-arg "ORCA_VERSION=${VERSION}" \
    --build-arg "ORCA_COMMIT=${COMMIT}" \
    --build-arg "ORCA_BUILD_DATE=${BUILD_DATE}" \
    --file "${REPO_ROOT}/packaging/docker/Dockerfile.release" \
    --output "type=local,dest=${OUT_DIR}" \
    "${REPO_ROOT}"

  test -x "${OUT_DIR}/linux-${arch}/orca"
  test -x "${OUT_DIR}/linux-${arch}/orca-daemon"
  file "${OUT_DIR}/linux-${arch}/orca" "${OUT_DIR}/linux-${arch}/orca-daemon"
done

echo "Docker-built Linux release binaries staged in ${OUT_DIR}"
