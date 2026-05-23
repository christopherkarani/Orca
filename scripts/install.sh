#!/usr/bin/env sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
DEFAULT_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION" 2>/dev/null || true)"
VERSION="${ORCA_VERSION:-${DEFAULT_VERSION:-1.1.4}}"
BASE_URL="${ORCA_BASE_URL:-https://github.com/christopherkarani/Orca/releases/download/v${VERSION}}"
INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/bin}"
ARTIFACT_DIR="${ORCA_ARTIFACT_DIR:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orca-install.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'orca install: %s\n' "$1" >&2
  exit 1
}

detect_os() {
  case "${ORCA_OS_OVERRIDE:-$(uname -s)}" in
    Darwin|darwin) printf 'darwin' ;;
    Linux|linux) printf 'linux' ;;
    *) fail "unsupported operating system: ${ORCA_OS_OVERRIDE:-$(uname -s)}" ;;
  esac
}

detect_arch() {
  case "${ORCA_ARCH_OVERRIDE:-$(uname -m)}" in
    x86_64|amd64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) fail "unsupported architecture: ${ORCA_ARCH_OVERRIDE:-$(uname -m)}" ;;
  esac
}

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$output"
  else
    fail "curl or wget is required to download release artifacts"
  fi
}

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    return 1
  fi
}

verify_checksum() {
  artifact_name="$1"
  artifact_path="$2"
  checksums_path="$3"

  [ -f "$checksums_path" ] || fail "checksums.txt not found; download it and verify manually before installing"
  expected="$(awk -v name="$artifact_name" '$2 == name {print $1}' "$checksums_path")"
  [ -n "$expected" ] || fail "no checksum entry found for $artifact_name"
  actual="$(sha256_file "$artifact_path")" || fail "no SHA-256 tool found; install sha256sum or shasum and retry"
  [ "$expected" = "$actual" ] || fail "checksum mismatch for $artifact_name"
}

is_existing_orca() {
  candidate="$1"
  output="$("$candidate" version 2>/dev/null)" || return 1
  printf '%s\n' "$output" | grep -Eqi '"product"[[:space:]]*:[[:space:]]*"orca"|^orca([[:space:]]|$)'
}

safe_install() {
  source_bin="$1"
  destination="$2"

  if [ -e "$destination" ] && [ "${ORCA_INSTALL_FORCE:-0}" != "1" ]; then
    if is_existing_orca "$destination"; then
      :
    else
      fail "refusing to overwrite non-Orca file at $destination; set ORCA_INSTALL_FORCE=1 to replace it"
    fi
  fi

  mkdir -p "$INSTALL_DIR"
  cp "$source_bin" "$destination"
  chmod 0755 "$destination"
}

rc_file_for_shell() {
  shell_name="$1"
  case "$shell_name" in
    */zsh) printf '%s' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    */bash)
      if [ -f "$HOME/.bashrc" ]; then
        printf '%s' "$HOME/.bashrc"
      elif [ -f "$HOME/.bash_profile" ]; then
        printf '%s' "$HOME/.bash_profile"
      else
        printf '%s' "$HOME/.bashrc"
      fi
      ;;
    */fish) printf '%s' "$HOME/.config/fish/config.fish" ;;
    *) printf '%s' "$HOME/.profile" ;;
  esac
}

ensure_path_entry() {
  dir="$1"
  shell_path="${SHELL:-/bin/sh}"
  shell_name="$(basename "$shell_path")"
  rc_file="$(rc_file_for_shell "$shell_path")"

  if [ ! -d "$(dirname "$rc_file")" ] && [ "$(dirname "$rc_file")" != "$HOME" ]; then
    mkdir -p "$(dirname "$rc_file")"
  fi

  if [ -f "$rc_file" ]; then
    if grep -qF "export PATH=\"$dir" "$rc_file" 2>/dev/null || grep -qF "export PATH=\"\$HOME/.local/bin" "$rc_file" 2>/dev/null; then
      return 0
    fi
  fi

  printf '\n# Added by Orca installer\nexport PATH="%s:$PATH"\n' "$dir" >> "$rc_file"
  printf 'Added %s to PATH in %s\n' "$dir" "$rc_file"
  printf 'Run: source %s   (or open a new terminal)\n' "$rc_file"
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
ARTIFACT="orca-v${VERSION}-${OS}-${ARCH}.tar.gz"

if [ -n "$ARTIFACT_DIR" ]; then
  [ -f "$ARTIFACT_DIR/$ARTIFACT" ] || fail "artifact not found: $ARTIFACT_DIR/$ARTIFACT"
  cp "$ARTIFACT_DIR/$ARTIFACT" "$TMP_DIR/$ARTIFACT"
  [ -f "$ARTIFACT_DIR/checksums.txt" ] || fail "checksums.txt not found in $ARTIFACT_DIR"
  cp "$ARTIFACT_DIR/checksums.txt" "$TMP_DIR/checksums.txt"
else
  download "$BASE_URL/$ARTIFACT" "$TMP_DIR/$ARTIFACT"
  download "$BASE_URL/checksums.txt" "$TMP_DIR/checksums.txt"
fi

verify_checksum "$ARTIFACT" "$TMP_DIR/$ARTIFACT" "$TMP_DIR/checksums.txt"
tar -xzf "$TMP_DIR/$ARTIFACT" -C "$TMP_DIR"

FOUND_BIN="$(find "$TMP_DIR" -type f -name orca -perm -111 | head -n 1)"
[ -n "$FOUND_BIN" ] || fail "artifact did not contain an executable orca binary"

DESTINATION="$INSTALL_DIR/orca"
safe_install "$FOUND_BIN" "$DESTINATION"

printf '\nInstalled Orca to %s\n' "$DESTINATION"

ensure_path_entry "$INSTALL_DIR"

printf '\nNext steps:\n'
printf '  orca --version\n'
printf '  orca doctor\n'
printf '  orca init --preset generic-agent\n'
