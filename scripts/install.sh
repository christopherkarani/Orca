#!/usr/bin/env sh
set -eu

# Orca installer (macOS / Linux)
#
# Documented one-liner:
#   curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh
#
# Environment:
#   ORCA_VERSION         Pin release version (default: latest / local VERSION / 1.2.0)
#   ORCA_INSTALL_DIR     Binary install dir (default: ~/.local/bin)
#   ORCA_SHARE_DIR       Runtime share root (default: ~/.local/share/orca)
#   ORCA_BASE_URL        Override release base URL
#   ORCA_ARTIFACT_DIR    Offline install from a local dist/ folder
#   ORCA_INSTALL_FORCE=1 Allow overwriting a non-Orca file at the destination
#   ORCA_INSTALL_QUIET=1 Suppress non-error UI (still installs; prints activation line)
#   NO_COLOR             Disable ANSI color even on a TTY
#
# Robust VERSION resolution (piped-safe):
# - File execution (dev, local checkout): read ../VERSION when present.
# - Piped public install (curl | sh): $0 is not a regular file, so we skip the
#   local read and fall through to the GitHub API (or ORCA_VERSION / 1.2.0).
# - ORCA_VERSION always wins. Hardcoded value is only the final safety net.

SCRIPT_DIR=""
if [ -f "$0" ] 2>/dev/null; then
  SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
fi

# ── Presentation ─────────────────────────────────────────────────────────────
# Quiet confidence: brand + named steps + one activation hero. Degrades cleanly
# for CI, pipes, NO_COLOR, and ORCA_INSTALL_QUIET. Glyphs match src/tui/render.zig
# (active/done markers use success green; narrative info uses cyan).

QUIET=0
if [ "${ORCA_INSTALL_QUIET:-0}" = "1" ]; then
  QUIET=1
fi

USE_COLOR=0
if [ "$QUIET" -eq 0 ] && [ -t 1 ] 2>/dev/null; then
  if [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    USE_COLOR=1
  fi
fi

if [ "$USE_COLOR" -eq 1 ]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')"
  C_RED="$(printf '\033[31m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_CYAN="$(printf '\033[36m')"
else
  C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
fi

ui_dim() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"
}

ui_info() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '  %s›%s %s\n' "$C_CYAN" "$C_RESET" "$*"
}

ui_err() {
  # Errors always print (including quiet mode).
  printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

print_banner() {
  version_label="$1"
  platform_label="$2"
  target_label="$3"
  [ "$QUIET" -eq 1 ] && return 0

  printf '\n'
  printf '  %s🛡  Orca%s · %sv%s%s\n' "$C_BOLD$C_CYAN" "$C_RESET" "$C_BOLD" "$version_label" "$C_RESET"
  if [ "$USE_COLOR" -eq 1 ]; then
    printf '  %s────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
  else
    printf '  --------------------------------\n'
  fi
  ui_dim "  Agent runtime protection · policy + daemon"
  printf '  %sPlatform%s  %s\n' "$C_DIM" "$C_RESET" "$platform_label"
  printf '  %sTarget%s    %s\n' "$C_DIM" "$C_RESET" "$target_label"
  printf '\n'
}

# Sequential phase markers (no in-place spinner in POSIX sh).
# Active marker color matches TUI stepLine: success token for active + done.
step_active() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '  %s›%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

step_done() {
  label="$1"
  detail="${2:-}"
  [ "$QUIET" -eq 1 ] && return 0
  if [ -n "$detail" ]; then
    printf '  %s✓%s %s  %s%s%s\n' "$C_GREEN" "$C_RESET" "$label" "$C_DIM" "$detail" "$C_RESET"
  else
    printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$label"
  fi
}

# fail MESSAGE [REMEDIATION]
# Prints a structured error and exits 1. Remediation may contain newlines.
fail() {
  msg="$1"
  remediation="${2:-}"
  printf '\n' >&2
  ui_err "$msg"
  if [ -n "$remediation" ]; then
    printf '%s\n' "$remediation" | while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && printf '    %s%s%s\n' "$C_DIM" "$line" "$C_RESET" >&2
    done
  fi
  printf '\n' >&2
  printf '  %sDocs%s  https://github.com/christopherkarani/Orca/blob/main/docs/install.md\n' "$C_DIM" "$C_RESET" >&2
  exit 1
}

# Single activation line (contract: /^    eval /). Always printed, including quiet.
print_activation() {
  quoted_destination="$1"
  printf '    eval "$(%s env 2>/dev/null || %s --print-install-env)"\n' \
    "$quoted_destination" "$quoted_destination"
}

# ── Version resolution ───────────────────────────────────────────────────────

DEFAULT_VERSION=""
if [ -n "$SCRIPT_DIR" ] && [ -r "${SCRIPT_DIR}/../VERSION" ]; then
  DEFAULT_VERSION="$(tr -d '[:space:]' < "${SCRIPT_DIR}/../VERSION" 2>/dev/null || true)"
fi

RESOLVED_FROM="default"
if [ -n "${ORCA_VERSION:-}" ]; then
  RESOLVED_FROM="ORCA_VERSION"
elif [ -n "${DEFAULT_VERSION}" ]; then
  RESOLVED_FROM="local VERSION"
elif [ -z "${ORCA_VERSION:-}" ]; then
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
        RESOLVED_FROM="GitHub latest"
        break
      fi
    fi
  done
fi

VERSION="${ORCA_VERSION:-${DEFAULT_VERSION:-1.2.0}}"
if [ -z "${ORCA_VERSION:-}" ] && [ -z "${DEFAULT_VERSION}" ]; then
  RESOLVED_FROM="fallback 1.2.0"
fi
BASE_URL="${ORCA_BASE_URL:-https://github.com/christopherkarani/Orca/releases/download/v${VERSION}}"
INSTALL_DIR="${ORCA_INSTALL_DIR:-${HOME}/.local/bin}"
SHARE_DIR="${ORCA_SHARE_DIR:-${HOME}/.local/share/orca}"
RESOURCE_ROOT="${SHARE_DIR}/${VERSION}"
CURRENT_LINK="${SHARE_DIR}/current"
ARTIFACT_DIR="${ORCA_ARTIFACT_DIR:-}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orca-install.XXXXXX")"
RUNTIME_DIRS="integrations fixtures schemas policies"
INSTALL_MARKER=".orca-installation"

# Profile notes collected during shell config (printed under Details).
PATH_NOTE=""
RESOURCE_NOTE=""
SHELL_NOTE=""
DASHBOARD_WARN=0
INSTALL_MODE="install"
PREVIOUS_LABEL=""

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

detect_os() {
  case "${ORCA_OS_OVERRIDE:-$(uname -s)}" in
    Darwin|darwin) printf 'darwin' ;;
    Linux|linux) printf 'linux' ;;
    *) fail "unsupported operating system: ${ORCA_OS_OVERRIDE:-$(uname -s)}" \
         "Orca's curl installer supports macOS and Linux only.
Windows: use scripts/install.ps1
Docs:    https://github.com/christopherkarani/Orca/blob/main/docs/install.md" ;;
  esac
}

detect_arch() {
  case "${ORCA_ARCH_OVERRIDE:-$(uname -m)}" in
    x86_64|amd64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) fail "unsupported architecture: ${ORCA_ARCH_OVERRIDE:-$(uname -m)}" \
         "Supported: amd64 (x86_64), arm64 (aarch64)." ;;
  esac
}

download_fail_remediation() {
  printf 'Check network access and that release v%s exists.
Retry: ORCA_VERSION=%s curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh' \
    "$VERSION" "$VERSION"
}

download() {
  url="$1"
  output="$2"
  if command -v curl >/dev/null 2>&1; then
    # Progress bar on TTY; silent otherwise (CI / quiet).
    if [ "$USE_COLOR" -eq 1 ] && [ "$QUIET" -eq 0 ]; then
      curl -fL --progress-bar "$url" -o "$output" || fail "download failed: $url" "$(download_fail_remediation)"
    else
      curl -fsSL "$url" -o "$output" || fail "download failed: $url" "$(download_fail_remediation)"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ "$USE_COLOR" -eq 1 ] && [ "$QUIET" -eq 0 ]; then
      wget --show-progress -q "$url" -O "$output" 2>&1 || wget -q "$url" -O "$output" || fail "download failed: $url" "$(download_fail_remediation)"
    else
      wget -q "$url" -O "$output" || fail "download failed: $url" "$(download_fail_remediation)"
    fi
  else
    fail "curl or wget is required to download release artifacts" \
      "Install curl, then re-run the installer."
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

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

verify_checksum() {
  artifact_name="$1"
  artifact_path="$2"
  checksums_path="$3"

  [ -f "$checksums_path" ] || fail "checksums.txt not found" \
    "Download checksums.txt with the archive and verify manually before installing.
Offline: set ORCA_ARTIFACT_DIR to a folder containing the archive + checksums.txt."
  expected="$(awk -v name="$artifact_name" '$2 == name {print $1}' "$checksums_path")"
  [ -n "$expected" ] || fail "no checksum entry found for $artifact_name" \
    "The release checksums.txt may not list this platform artifact yet."
  actual="$(sha256_file "$artifact_path")" || fail "no SHA-256 tool found" \
    "Install sha256sum (coreutils) or shasum and retry."
  if [ "$expected" != "$actual" ]; then
    fail "checksum mismatch for $artifact_name" \
      "Expected: ${expected}
Got:      ${actual}
Refuse to install a corrupted or tampered archive.
Retry:    ORCA_VERSION=${VERSION} curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh
Offline:  set ORCA_ARTIFACT_DIR after verifying checksums by hand."
  fi
}

# Probe an existing binary once: sets _PROBE_VERSION when it looks like Orca.
# Avoids double-invoking the binary for install-mode + version label.
probe_existing_orca() {
  candidate="$1"
  _PROBE_VERSION=""
  [ -e "$candidate" ] || return 1
  out="$("$candidate" version 2>/dev/null)" || out="$("$candidate" --version 2>/dev/null)" || return 1
  printf '%s\n' "$out" | grep -Eqi '"product"[[:space:]]*:[[:space:]]*"orca"|^orca(-daemon)?([[:space:]]|$)|^[0-9]+\.[0-9]+\.[0-9]+' || return 1
  # Prefer a dotted semver token (sed for broader POSIX portability than grep -oE).
  _PROBE_VERSION="$(printf '%s\n' "$out" | sed -n 's/.*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n1 || true)"
  return 0
}

is_existing_orca() {
  probe_existing_orca "$1"
}

safe_install() {
  source_bin="$1"
  destination="$2"

  if [ -e "$destination" ] && [ "${ORCA_INSTALL_FORCE:-0}" != "1" ]; then
    if is_existing_orca "$destination"; then
      :
    else
      fail "refusing to overwrite non-Orca file at $destination" \
        "Set ORCA_INSTALL_FORCE=1 to replace it, or choose another ORCA_INSTALL_DIR."
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
      fail "release archive missing runtime directory: $dir" \
        "Re-download the official release artifact for v${VERSION}."
    fi
  done
  if [ -d "$extract_root/orca-dashboard-ui" ]; then
    rm -rf "$RESOURCE_ROOT/orca-dashboard-ui"
    cp -R "$extract_root/orca-dashboard-ui" "$RESOURCE_ROOT/"
  else
    DASHBOARD_WARN=1
  fi
  {
    printf 'orca-runtime-v1\n'
    printf 'version=%s\n' "$VERSION"
  } > "$RESOURCE_ROOT/$INSTALL_MARKER"
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

  marker="# Added by Orca installer"
  quoted_dir="$(shell_quote "$dir")"
  if [ "$shell_name" = "fish" ]; then
    path_line="fish_add_path -- $quoted_dir"
  else
    path_line="export PATH=$quoted_dir:\"\$PATH\""
  fi

  if [ -f "$rc_file" ] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v marker="$marker" -v new_line="$path_line" '
      $0 == marker { print; print new_line; skip=1; next }
      skip && (/^export PATH=/ || /^fish_add_path -- /) { next }
      skip && $0 == "" { skip=0 }
      { print }
    ' "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
    PATH_NOTE="updated PATH in ${rc_file}"
    return 0
  fi

  printf '\n%s\n%s\n' "$marker" "$path_line" >> "$rc_file"
  PATH_NOTE="added PATH in ${rc_file}"
  SHELL_NOTE="source ${rc_file}  (or open a new terminal)"
}

ensure_resource_root_entry() {
  shell_path="${SHELL:-/bin/sh}"
  shell_name="$(basename "$shell_path")"
  rc_file="$(rc_file_for_shell "$shell_path")"
  marker="# Orca runtime assets"
  quoted_current="$(shell_quote "$CURRENT_LINK")"
  if [ "$shell_name" = "fish" ]; then
    resource_line="set -gx ORCA_RESOURCE_ROOT $quoted_current"
  else
    resource_line="export ORCA_RESOURCE_ROOT=$quoted_current"
  fi

  if [ ! -d "$(dirname "$rc_file")" ] && [ "$(dirname "$rc_file")" != "$HOME" ]; then
    mkdir -p "$(dirname "$rc_file")"
  fi

  if [ -f "$rc_file" ] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
    tmp="$(mktemp)"
    awk -v marker="$marker" -v new_line="$resource_line" '
      $0 == marker { print; print new_line; skip=1; next }
      skip && (/^export ORCA_RESOURCE_ROOT=/ || /^set -gx ORCA_RESOURCE_ROOT /) { next }
      skip && $0 == "" { skip=0 }
      { print }
    ' "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
    RESOURCE_NOTE="updated ORCA_RESOURCE_ROOT in ${rc_file}"
    return 0
  fi

  {
    printf '\n%s\n' "$marker"
    printf '%s\n' "$resource_line"
  } >> "$rc_file"
  RESOURCE_NOTE="added ORCA_RESOURCE_ROOT in ${rc_file}"
}

# Read-only host soft-detect (does not configure hooks — that is orca setup).
# Format: "name:bin_or_empty:dir_or_empty" — bin checked via command -v; dir via -d.
detect_hosts() {
  found=""
  # openclaw: binary only (no stable home dir). Others: binary or config dir.
  for spec in \
    "claude:claude:${HOME}/.claude" \
    "codex:codex:${HOME}/.codex" \
    "opencode:opencode:${HOME}/.config/opencode" \
    "openclaw:openclaw:" \
    "hermes:hermes:${HOME}/.hermes"
  do
    name="${spec%%:*}"
    rest="${spec#*:}"
    bin="${rest%%:*}"
    dir="${rest#*:}"
    if command -v "$bin" >/dev/null 2>&1; then
      found="${found} ${name}"
    elif [ -n "$dir" ] && [ -d "$dir" ]; then
      found="${found} ${name}"
    fi
  done
  printf '%s' "${found# }"
}

print_host_hints() {
  hosts="$1"
  [ "$QUIET" -eq 1 ] && return 0
  [ -z "$hosts" ] && return 0
  printf '\n'
  printf '  %sDetected hosts%s (not configured yet)\n' "$C_BOLD" "$C_RESET"
  for h in $hosts; do
    printf '  %s·%s %-10s %sfound%s\n' "$C_DIM" "$C_RESET" "$h" "$C_DIM" "$C_RESET"
  done
  ui_dim "  Wire them with: orca setup"
}

print_success() {
  hosts="$1"
  quoted_destination="$2"

  [ "$QUIET" -eq 1 ] && return 0

  printf '\n'
  case "$INSTALL_MODE" in
    upgrade)
      printf '  %s✓%s  %sOrca v%s installed%s  %s(upgraded from %s)%s\n' \
        "$C_GREEN" "$C_RESET" "$C_BOLD" "$VERSION" "$C_RESET" "$C_DIM" "$PREVIOUS_LABEL" "$C_RESET"
      ;;
    reinstall)
      printf '  %s✓%s  %sOrca v%s reinstalled%s\n' \
        "$C_GREEN" "$C_RESET" "$C_BOLD" "$VERSION" "$C_RESET"
      ;;
    *)
      printf '  %s✓%s  %sOrca v%s installed%s\n' \
        "$C_GREEN" "$C_RESET" "$C_BOLD" "$VERSION" "$C_RESET"
      ;;
  esac
  ui_dim "  Daemon + runtime ready"

  printf '\n'
  printf '  %sActivate this terminal%s\n' "$C_BOLD" "$C_RESET"
  ui_dim "  (INSTALL_DIR is not on PATH in this shell yet)"
  printf '\n'
  print_activation "$quoted_destination"
  printf '\n'
  ui_dim "  Profile exports were also written for future terminals."

  printf '\n'
  printf '  %sThen%s\n' "$C_BOLD" "$C_RESET"
  printf '    orca doctor\n'
  printf '    orca setup          %s# guided host wiring (TTY); --auto for CI%s\n' "$C_DIM" "$C_RESET"

  print_host_hints "$hosts"

  # Part of the success receipt (stdout), not a side-channel on stderr.
  if [ "$DASHBOARD_WARN" -eq 1 ]; then
    printf '\n'
    printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" \
      "Release archive missing orca-dashboard-ui; reinstall a complete artifact for the dashboard."
  fi

  printf '\n'
  printf '  %sDetails%s\n' "$C_DIM" "$C_RESET"
  printf '  %s  binary   %s%s\n' "$C_DIM" "$DESTINATION" "$C_RESET"
  printf '  %s  daemon   %s%s\n' "$C_DIM" "$DAEMON_DESTINATION" "$C_RESET"
  printf '  %s  assets   %s → %s%s\n' "$C_DIM" "$CURRENT_LINK" "$RESOURCE_ROOT" "$C_RESET"
  if [ -n "$PATH_NOTE" ]; then
    printf '  %s  path     %s%s\n' "$C_DIM" "$PATH_NOTE" "$C_RESET"
  fi
  if [ -n "$RESOURCE_NOTE" ]; then
    printf '  %s  env      %s%s\n' "$C_DIM" "$RESOURCE_NOTE" "$C_RESET"
  fi
  if [ -n "$SHELL_NOTE" ]; then
    printf '  %s  shell    %s%s\n' "$C_DIM" "$SHELL_NOTE" "$C_RESET"
  fi
  printf '\n'
}

# ── Main ─────────────────────────────────────────────────────────────────────

OS="$(detect_os)"
ARCH="$(detect_arch)"
ARTIFACT="orca-v${VERSION}-${OS}-${ARCH}.tar.gz"
DESTINATION="$INSTALL_DIR/orca"
DAEMON_DESTINATION="$INSTALL_DIR/orca-daemon"

# Detect existing install before overwrite (single binary probe for mode + label).
if probe_existing_orca "$DESTINATION"; then
  PREVIOUS_LABEL="$_PROBE_VERSION"
  if [ -n "$PREVIOUS_LABEL" ] && [ "$PREVIOUS_LABEL" != "$VERSION" ]; then
    INSTALL_MODE="upgrade"
  else
    INSTALL_MODE="reinstall"
    if [ -z "$PREVIOUS_LABEL" ]; then
      PREVIOUS_LABEL="installed"
    fi
  fi
fi

print_banner "$VERSION" "${OS}/${ARCH}" "$INSTALL_DIR"

step_done "Resolve release" "v${VERSION} (${RESOLVED_FROM})"

if [ "$INSTALL_MODE" = "upgrade" ]; then
  ui_info "Upgrading ${PREVIOUS_LABEL} → ${VERSION}"
elif [ "$INSTALL_MODE" = "reinstall" ]; then
  ui_info "Reinstalling v${VERSION}"
fi

if [ -n "$ARTIFACT_DIR" ]; then
  [ -f "$ARTIFACT_DIR/$ARTIFACT" ] || fail "artifact not found: $ARTIFACT_DIR/$ARTIFACT" \
    "Expected ${ARTIFACT} under ORCA_ARTIFACT_DIR."
  cp "$ARTIFACT_DIR/$ARTIFACT" "$TMP_DIR/$ARTIFACT"
  [ -f "$ARTIFACT_DIR/checksums.txt" ] || fail "checksums.txt not found in $ARTIFACT_DIR" \
    "Place checksums.txt next to the archive for offline install."
  cp "$ARTIFACT_DIR/checksums.txt" "$TMP_DIR/checksums.txt"
  step_done "Use local artifacts" "$ARTIFACT_DIR"
else
  # Active marker only for the network-bound phase (can take a while).
  step_active "Download archive"
  download "$BASE_URL/$ARTIFACT" "$TMP_DIR/$ARTIFACT"
  download "$BASE_URL/checksums.txt" "$TMP_DIR/checksums.txt"
  step_done "Download archive" "$ARTIFACT"
fi

verify_checksum "$ARTIFACT" "$TMP_DIR/$ARTIFACT" "$TMP_DIR/checksums.txt"
step_done "Verify SHA-256" "ok"

step_active "Install binaries + runtime"
# Extract while suppressing only the harmless macOS provenance xattr noise that appears
# when Linux extracts tarballs produced on macOS (or that carry extended attributes).
# Real tar failures still cause the script to abort via the subsequent checks.
tar -xzf "$TMP_DIR/$ARTIFACT" -C "$TMP_DIR" 2>"$TMP_DIR/.tar.err" || {
  grep -v 'LIBARCHIVE.xattr.com.apple.provenance' "$TMP_DIR/.tar.err" | \
    grep -v 'Ignoring unknown extended header keyword' >&2 || true
  rm -f "$TMP_DIR/.tar.err"
  fail "tar extraction failed" \
    "The archive may be corrupt. Re-download and verify checksums."
}
rm -f "$TMP_DIR/.tar.err"

EXTRACT_ROOT="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$EXTRACT_ROOT" ] || fail "artifact did not contain an extracted release root" \
  "Unexpected archive layout for ${ARTIFACT}."

FOUND_BIN="$(find "$EXTRACT_ROOT" -type f -name orca -perm -111 | head -n 1)"
[ -n "$FOUND_BIN" ] || fail "artifact did not contain an executable orca binary" \
  "Unexpected archive layout for ${ARTIFACT}."
FOUND_DAEMON="$(find "$EXTRACT_ROOT" -type f -name orca-daemon -perm -111 | head -n 1)"
[ -n "$FOUND_DAEMON" ] || fail "artifact did not contain an executable orca-daemon binary" \
  "Unexpected archive layout for ${ARTIFACT}."

safe_install "$FOUND_BIN" "$DESTINATION"
safe_install "$FOUND_DAEMON" "$DAEMON_DESTINATION"
install_runtime_assets "$EXTRACT_ROOT"
step_done "Install binaries + runtime" "orca, orca-daemon, assets"

ensure_path_entry "$INSTALL_DIR"
ensure_resource_root_entry "$CURRENT_LINK"
step_done "Configure shell" "PATH + ORCA_RESOURCE_ROOT"

# Host soft-detect (read-only) after install so PATH may include more tools.
DETECTED_HOSTS="$(detect_hosts)"
quoted_destination="$(shell_quote "$DESTINATION")"

print_success "$DETECTED_HOSTS" "$quoted_destination"

# Quiet mode still prints the activation line so automation can parse it.
if [ "$QUIET" -eq 1 ]; then
  print_activation "$quoted_destination"
fi
