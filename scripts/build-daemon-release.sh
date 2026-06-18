#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OS="${1:-${ORCA_TARGET_OS:-}}"
ARCH="${2:-${ORCA_TARGET_ARCH:-}}"
OUT_DIR="${3:-${ORCA_DAEMON_ARTIFACT_DIR:-${REPO_ROOT}/dist/daemon-artifacts}}"

fail() {
  printf 'build-daemon-release: %s\n' "$1" >&2
  exit 1
}

[ -n "$OS" ] || fail "usage: $0 <os> <arch> [out-dir]"
[ -n "$ARCH" ] || fail "usage: $0 <os> <arch> [out-dir]"

case "${OS}-${ARCH}" in
  darwin-amd64)
    rust_target="x86_64-apple-darwin"
    daemon_name="orca-daemon"
    ;;
  darwin-arm64)
    rust_target="aarch64-apple-darwin"
    daemon_name="orca-daemon"
    ;;
  linux-amd64)
    rust_target="x86_64-unknown-linux-gnu"
    daemon_name="orca-daemon"
    ;;
  linux-arm64)
    rust_target="aarch64-unknown-linux-gnu"
    daemon_name="orca-daemon"
    ;;
  windows-amd64)
    rust_target="x86_64-pc-windows-msvc"
    daemon_name="orca-daemon.exe"
    ;;
  *)
    fail "unsupported target: ${OS}-${ARCH}"
    ;;
esac

if command -v rustup >/dev/null 2>&1; then
  rustup target add "$rust_target" >/dev/null 2>&1 || true
fi

printf 'Building Rust daemon for %s (%s)\n' "${OS}-${ARCH}" "$rust_target"
(cd "${REPO_ROOT}/orca-rs" && cargo build --release --locked --target "$rust_target")

source_path="${REPO_ROOT}/orca-rs/target/${rust_target}/release/${daemon_name}"
[ -f "$source_path" ] || fail "missing built daemon artifact: $source_path"

target_dir="${OUT_DIR}/${OS}-${ARCH}"
mkdir -p "$target_dir"
cp -p "$source_path" "${target_dir}/${daemon_name}"

printf 'Staged %s\n' "${target_dir}/${daemon_name}"
