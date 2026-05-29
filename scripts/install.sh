#!/usr/bin/env sh
set -eu

# Robust VERSION resolution (piped-safe):
# - File execution (dev, local checkout): read ../VERSION when present.
# - Piped public install (curl | sh — the primary documented path): $0 is not a
#   regular file, so we skip the local read entirely (no redirection noise) and
#   fall through to the GitHub API query (or ORCA_VERSION / hardcoded 1.1.5).
# - ORCA_VERSION always wins. Hardcoded value is only the final safety net.
SCRIPT_DIR=""
if [ -f "$0" ] 2>/dev/null; then
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi

DEFAULT_VERSION=""
if [ -n "$SCRIPT_DIR" ] && [ -r "${SCRIPT_DIR}/../VERSION" ]; then
    DEFAULT_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION" 2>/dev/null || true)"
fi

if [ -z "${DEFAULT_VERSION}" ] && [ -z "${ORCA_VERSION:-}" ]; then
    # Piped / non-filesystem execution path. Best-effort latest release.
    for _url in "https://api.github.com/repos/christopherkarani/Orca/releases/latest"; do
        _resp=""
        if command -v curl >/dev/null 2>&1; then
            _resp="$(curl -fsSL --max-time 8 -H "User-Agent: orca-install-script/1.0 (github.com/christopherkarani/Orca)" "$_url" 2>/dev/null || true)"
        elif command -v wget >/dev/null 2>&1; then
            _resp="$(wget -qO- --timeout=8 --user-agent="orca-install-script/1.0 (github.com/christopherkarani/Orca)" "$_url" 2>/dev/null || true)"
        fi
        if [ -n "${_resp:-}" ]; then
            _tag="$(printf '%s' "$_resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[vV]*[^"]*"' | head -n1 | \
                sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"[vV]?([^"]*)".*/\1/' || true)"
            if [ -n "${_tag:-}" ]; then
                DEFAULT_VERSION="$_tag"
                break
            fi
        fi
    done
fi

VERSION="${ORCA_VERSION:-${DEFAULT_VERSION:-1.1.5}}"
BASE_URL="${ORCA_BASE_URL:-https://github.com/christopherkarani/Orca/releases/download/v${VERSION}}"
INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/bin}"
SHARE_DIR="${ORCA_SHARE_DIR:-${HOME}/.local/share/orca}"
RESOURCE_ROOT="${ORCA_RESOURCE_ROOT:-${SHARE_DIR}/${VERSION}}"
CURRENT_LINK="${SHARE_DIR}/current"
ARTIFACT_DIR="${ORCA_ARTIFACT_DIR:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orca-install.XXXXXX")"
RUNTIME_DIRS="integrations fixtures schemas policies"

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

install_runtime_assets() {
  extract_root="$1"
  mkdir -p "$RESOURCE_ROOT"
  for dir in $RUNTIME_DIRS; do
    if [ -d "$extract_root/$dir" ]; then
      rm -rf "$RESOURCE_ROOT/$dir"
      cp -R "$extract_root/$dir" "$RESOURCE_ROOT/"
    else
      fail "release archive missing runtime directory: $dir"
    fi
  done
  mkdir -p "$SHARE_DIR"
  ln -sfn "$RESOURCE_ROOT" "$CURRENT_LINK"
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

ensure_resource_root_entry() {
  shell_path="${SHELL:-/bin/sh}"
  rc_file="$(rc_file_for_shell "$shell_path")"
  marker="# Orca runtime assets"

  if [ ! -d "$(dirname "$rc_file")" ] && [ "$(dirname "$rc_file")" != "$HOME" ]; then
    mkdir -p "$(dirname "$rc_file")"
  fi

  if [ -f "$rc_file" ] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v marker="$marker" -v new_line="export ORCA_RESOURCE_ROOT=\"${CURRENT_LINK}\"" '
      $0 == marker { print; print new_line; skip=1; next }
      skip && /^export ORCA_RESOURCE_ROOT=/ { next }
      skip && $0 == "" { skip=0 }
      { print }
    ' "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
    printf 'Updated ORCA_RESOURCE_ROOT=%s in %s\n' "$CURRENT_LINK" "$rc_file"
    return 0
  fi

  {
    printf '\n%s\n' "$marker"
    printf 'export ORCA_RESOURCE_ROOT="%s"\n' "$CURRENT_LINK"
  } >> "$rc_file"
  printf 'Added ORCA_RESOURCE_ROOT=%s to %s\n' "$CURRENT_LINK" "$rc_file"
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

# Extract while suppressing only the harmless macOS provenance xattr noise that appears
# when Linux extracts tarballs produced on macOS (or that carry extended attributes).
# Real tar failures still cause the script to abort via the subsequent checks.
tar -xzf "$TMP_DIR/$ARTIFACT" -C "$TMP_DIR" 2>"$TMP_DIR/.tar.err" || {
  grep -v 'LIBARCHIVE.xattr.com.apple.provenance' "$TMP_DIR/.tar.err" | \
    grep -v 'Ignoring unknown extended header keyword' >&2 || true
  rm -f "$TMP_DIR/.tar.err"
  fail "tar extraction failed"
}
rm -f "$TMP_DIR/.tar.err"

EXTRACT_ROOT="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$EXTRACT_ROOT" ] || fail "artifact did not contain an extracted release root"

FOUND_BIN="$(find "$EXTRACT_ROOT" -type f -name orca -perm -111 | head -n 1)"
[ -n "$FOUND_BIN" ] || fail "artifact did not contain an executable orca binary"

DESTINATION="$INSTALL_DIR/orca"
safe_install "$FOUND_BIN" "$DESTINATION"
install_runtime_assets "$EXTRACT_ROOT"

printf '\nInstalled Orca to %s\n' "$DESTINATION"
printf 'Installed runtime assets to %s\n' "$RESOURCE_ROOT"
printf 'Current runtime symlink: %s -> %s\n' "$CURRENT_LINK" "$RESOURCE_ROOT"
printf 'ORCA_RESOURCE_ROOT=%s\n' "$CURRENT_LINK"

ensure_path_entry "$INSTALL_DIR"
ensure_resource_root_entry "$CURRENT_LINK"

# Highest-value DX improvement: give users an immediate activation block they can paste
# in the *current* shell. This directly attacks the #1 source of "30 seconds" being false.
# Uses the new `orca env` (or --print-install-env for compat) so the paths are always
# correct for the actual install layout (including custom prefixes and Windows).
printf '\nTo use orca in *this* terminal right now (without opening a new one), run:\n'
printf '\n    eval "$(orca env 2>/dev/null || orca --print-install-env)"\n'
printf '\n(These exports were also added to your shell profile for future terminals.)\n'

printf '\nNext steps:\n'
printf '  orca --version\n'
printf '  orca doctor\n'
printf '  orca setup          # guided interactive host selection (TTY); --auto for CI\n'
printf '  (optional) orca plugin list\n'
