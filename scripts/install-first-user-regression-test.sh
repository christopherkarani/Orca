#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

fail() {
  printf 'install-first-user-regression: %s\n' "$1" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) fail "unsupported host OS" ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) fail "unsupported host architecture" ;;
esac

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/orca-first-user.XXXXXX")"
cleanup() {
  rm -rf "${tmp_root}"
}
trap cleanup EXIT INT TERM

home="${tmp_root}/home"
escaped="${tmp_root}/escaped"
install_dir="${home}/bin \$(touch PATH_INJECTION)"
share_dir="${home}/share \$(touch RESOURCE_INJECTION)"
artifact_dir="${tmp_root}/artifacts"
release_root="${tmp_root}/orca-v${VERSION}-${os}-${arch}"
artifact="orca-v${VERSION}-${os}-${arch}.tar.gz"
mkdir -p "${home}" "${artifact_dir}" "${release_root}/bin"

for dir in integrations fixtures schemas policies; do
  mkdir -p "${release_root}/${dir}"
  printf 'fixture\n' > "${release_root}/${dir}/fixture.txt"
done

cat > "${release_root}/bin/orca" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in
  env|--print-install-env)
    printf 'export ORCA_FIRST_USER_ACTIVATED=1\n'
    ;;
  version|--version)
    printf 'orca 0.0.0\n'
    ;;
esac
EOF
cat > "${release_root}/bin/orca-daemon" <<'EOF'
#!/usr/bin/env sh
case "${1:-}" in
  version|--version) printf 'orca-daemon 0.0.0\n' ;;
esac
EOF
chmod +x "${release_root}/bin/orca" "${release_root}/bin/orca-daemon"
tar -czf "${artifact_dir}/${artifact}" -C "${tmp_root}" "$(basename "${release_root}")"
if command -v sha256sum >/dev/null 2>&1; then
  checksum="$(sha256sum "${artifact_dir}/${artifact}" | awk '{print $1}')"
else
  checksum="$(shasum -a 256 "${artifact_dir}/${artifact}" | awk '{print $1}')"
fi
printf '%s  %s\n' "${checksum}" "${artifact}" > "${artifact_dir}/checksums.txt"

output="$(
  HOME="${home}" \
  SHELL=/bin/sh \
  ORCA_VERSION="${VERSION}" \
  ORCA_ARTIFACT_DIR="${artifact_dir}" \
  ORCA_INSTALL_DIR="${install_dir}" \
  ORCA_SHARE_DIR="${share_dir}" \
  ORCA_RESOURCE_ROOT="${escaped}" \
  sh "${REPO_ROOT}/scripts/install.sh"
)"

# Reinstalling must update the managed blocks instead of appending duplicates.
HOME="${home}" \
SHELL=/bin/sh \
ORCA_VERSION="${VERSION}" \
ORCA_ARTIFACT_DIR="${artifact_dir}" \
ORCA_INSTALL_DIR="${install_dir}" \
ORCA_SHARE_DIR="${share_dir}" \
sh "${REPO_ROOT}/scripts/install.sh" >/dev/null
[[ "$(grep -c '^# Added by Orca installer$' "${home}/.profile")" == 1 ]] || fail "reinstall duplicated the PATH block"
[[ "$(grep -c '^# Orca runtime assets$' "${home}/.profile")" == 1 ]] || fail "reinstall duplicated the runtime block"

[[ ! -e "${escaped}" ]] || fail "ORCA_RESOURCE_ROOT escaped the install destination"
resource_root="${share_dir}/${VERSION}"
[[ -f "${resource_root}/fixtures/fixture.txt" ]] || fail "runtime assets were not installed under HOME"
[[ "$(readlink "${share_dir}/current")" == "${resource_root}" ]] || fail "current link targets the wrong runtime root"

activation="$(printf '%s\n' "${output}" | awk '/^    eval / { sub(/^    /, ""); print; exit }')"
[[ -n "${activation}" ]] || fail "installer did not print an activation command"
[[ "${activation}" == *"${install_dir}/orca"* ]] || fail "activation command does not use the absolute installed binary"
unset ORCA_FIRST_USER_ACTIVATED
eval "${activation}"
[[ "${ORCA_FIRST_USER_ACTIVATED:-}" == 1 ]] || fail "printed activation command did not activate the current shell"

(
  cd "${home}"
  # shellcheck disable=SC1090
  . "${home}/.profile"
)
[[ ! -e "${home}/PATH_INJECTION" ]] || fail "install path executed shell syntax from the profile"
[[ ! -e "${home}/RESOURCE_INJECTION" ]] || fail "resource path executed shell syntax from the profile"

printf '[install-first-user-regression] passed\n'
