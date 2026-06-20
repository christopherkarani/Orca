#!/usr/bin/env sh
set -eu

VERSION="${ORCA_VERSION:-$(tr -d '[:space:]' <"$(dirname "$0")/../VERSION" 2>/dev/null || printf '1.2.0')}"
COMMIT="${ORCA_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || printf unknown)}"
BUILD_DATE="${ORCA_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
ZIG_OPTIMIZE="${ORCA_ZIG_OPTIMIZE:-ReleaseSafe}"
RELEASE_PRODUCT="${ORCA_RELEASE_PRODUCT:-all}"
DAEMON_ARTIFACT_DIR="${ORCA_DAEMON_ARTIFACT_DIR:-}"
SIGNING_STATUS="not_configured"

HOST_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
x86_64) HOST_ARCH="amd64" ;;
aarch64 | arm64) HOST_ARCH="arm64" ;;
esac

# Phase 41 artifact contract:
# - orca-v1.1.0-darwin-amd64.tar.gz
# - orca-v1.1.0-darwin-arm64.tar.gz
# - orca-v1.1.0-linux-amd64.tar.gz
# - orca-v1.1.0-linux-arm64.tar.gz
# - orca-v1.1.0-windows-amd64.zip
# Release archive names and installed binaries use Orca/Core names only.

CLI_TARGETS="
darwin amd64 x86_64-macos tar.gz orca
darwin arm64 aarch64-macos tar.gz orca
linux amd64 x86_64-linux tar.gz orca
linux arm64 aarch64-linux tar.gz orca
windows amd64 x86_64-windows zip orca.exe
"

daemon_name_for_os() {
  case "$1" in
    windows) printf 'orca-daemon.exe' ;;
    *) printf 'orca-daemon' ;;
  esac
}

rust_target_for() {
  case "$1-$2" in
    darwin-amd64) printf 'x86_64-apple-darwin' ;;
    darwin-arm64) printf 'aarch64-apple-darwin' ;;
    linux-amd64) printf 'x86_64-unknown-linux-gnu' ;;
    linux-arm64) printf 'aarch64-unknown-linux-gnu' ;;
    windows-amd64) printf 'x86_64-pc-windows-msvc' ;;
    *) return 1 ;;
  esac
}

selected_targets() {
  case "$RELEASE_PRODUCT" in
    all | cli)
      printf '%s\n' "$CLI_TARGETS"
      ;;
    host)
      case "$HOST_OS-$HOST_ARCH" in
        darwin-amd64) printf 'darwin amd64 x86_64-macos tar.gz orca\n' ;;
        darwin-arm64) printf 'darwin arm64 aarch64-macos tar.gz orca\n' ;;
        linux-amd64) printf 'linux amd64 x86_64-linux tar.gz orca\n' ;;
        linux-arm64) printf 'linux arm64 aarch64-linux tar.gz orca\n' ;;
        windows-amd64) printf 'windows amd64 x86_64-windows zip orca.exe\n' ;;
        *) printf 'build-release: unsupported host target for release dry-run: %s-%s\n' "$HOST_OS" "$HOST_ARCH" >&2; exit 1 ;;
      esac
      ;;
    *)
      printf 'build-release: unsupported ORCA_RELEASE_PRODUCT=%s (expected all, cli, or host)\n' "$RELEASE_PRODUCT" >&2
      exit 1
      ;;
  esac
}

target_platforms_json() {
  case "$RELEASE_PRODUCT" in
    all | cli) printf '["darwin-amd64", "darwin-arm64", "linux-amd64", "linux-arm64", "windows-amd64"]' ;;
    host) printf '["%s-%s"]' "$HOST_OS" "$HOST_ARCH" ;;
    *) printf '[]' ;;
  esac
}

copy_cli_payload() {
  root="$1"
  mkdir -p "$root"
  cp README.md LICENSE SECURITY.md CONTRIBUTING.md "$root/"
  cp -R docs policies schemas fixtures examples packages packaging scripts integrations "$root/"
  if [ -d "orca-dashboard-ui/dist" ]; then
    mkdir -p "$root/orca-dashboard-ui"
    cp -R orca-dashboard-ui/dist "$root/orca-dashboard-ui/dist"
  else
    printf 'warning: orca-dashboard-ui/dist not found; run `npm run build` in orca-dashboard-ui/ before releasing.\n' >&2
  fi
  find "$root" -type d \( \
    -name node_modules -o \
    -name .pnpm-store -o \
    -name .yarn -o \
    -name .turbo -o \
    -name .cache \
    \) -prune -exec rm -rf {} +
  rm -rf \
    "$root/docs/integrations/drone-safepoint.md" \
    "$root/docs/integrations/drone-safety.md" \
    "$root/schemas/safety-report"* \
    "$root/.DS_Store" \
    "$root/docs/.DS_Store" \
    "$root/packages/.DS_Store" \
    "$root/examples/.DS_Store" \
    "$root/orca-dashboard-ui/node_modules" 2>/dev/null || true
}

write_release_readme() {
  root="$1"
  title="Orca/Core ${VERSION} Release Artifact"
  boundary="This archive contains the Orca CLI plus Core policy, audit, replay, redaction, schema, integration, and packaging resources needed by Orca. Edge runtime, drone, SITL, and customer-pilot materials are intentionally excluded."
  cat >"$root/README-release.md" <<EOF
# ${title}

This artifact is built from commit ${COMMIT} at ${BUILD_DATE}.

Verify the archive against the top-level checksums.txt before installing:

\`\`\`sh
sha256sum -c checksums.txt
\`\`\`

${boundary}
EOF
}

daemon_artifact_path() {
  os="$1"
  arch="$2"
  daemon_name="$(daemon_name_for_os "$os")"

  if [ -n "$DAEMON_ARTIFACT_DIR" ] && [ -f "${DAEMON_ARTIFACT_DIR}/${os}-${arch}/${daemon_name}" ]; then
    printf '%s\n' "${DAEMON_ARTIFACT_DIR}/${os}-${arch}/${daemon_name}"
    return 0
  fi

  if [ "$os" = "$HOST_OS" ] && [ "$arch" = "$HOST_ARCH" ]; then
    ./scripts/build-daemon-release.sh "$os" "$arch" "${DIST_DIR}/daemon-artifacts" >/dev/null
    printf '%s\n' "${DIST_DIR}/daemon-artifacts/${os}-${arch}/${daemon_name}"
    return 0
  fi

  printf 'build-release: missing staged daemon artifact for %s-%s; build it via ./scripts/build-daemon-release.sh or provide ORCA_DAEMON_ARTIFACT_DIR\n' "$os" "$arch" >&2
  exit 1
}

verify_daemon_binary_target() {
  os="$1"
  arch="$2"
  daemon_path="$3"

  if ! command -v file >/dev/null 2>&1; then
    printf 'warning: `file` not available; skipping daemon target verification for %s\n' "$daemon_path" >&2
    return 0
  fi

  description="$(file "$daemon_path")"
  case "${os}-${arch}" in
    darwin-amd64)
      printf '%s' "$description" | grep -Eq 'Mach-O .*x86_64' || {
        printf 'build-release: daemon artifact %s is not a darwin-amd64 binary\n' "$daemon_path" >&2
        exit 1
      }
      ;;
    darwin-arm64)
      printf '%s' "$description" | grep -Eq 'Mach-O .*arm64' || {
        printf 'build-release: daemon artifact %s is not a darwin-arm64 binary\n' "$daemon_path" >&2
        exit 1
      }
      ;;
    linux-amd64)
      printf '%s' "$description" | grep -Eq 'ELF 64-bit .*x86-64' || {
        printf 'build-release: daemon artifact %s is not a linux-amd64 binary\n' "$daemon_path" >&2
        exit 1
      }
      ;;
    linux-arm64)
      printf '%s' "$description" | grep -Eq 'ELF 64-bit .*ARM aarch64' || {
        printf 'build-release: daemon artifact %s is not a linux-arm64 binary\n' "$daemon_path" >&2
        exit 1
      }
      ;;
    windows-amd64)
      printf '%s' "$description" | grep -Eq 'PE32\+ executable .*x86-64' || {
        printf 'build-release: daemon artifact %s is not a windows-amd64 binary\n' "$daemon_path" >&2
        exit 1
      }
      ;;
    *)
      printf 'build-release: unsupported daemon verification target: %s-%s\n' "$os" "$arch" >&2
      exit 1
      ;;
  esac
}

build_cli_target() {
  os="$1"
  arch="$2"
  zig_target="$3"
  ext="$4"
  bin_name="$5"

  artifact="orca-v${VERSION}-${os}-${arch}.${ext}"
  work="${DIST_DIR}/work/cli-${os}-${arch}"
  prefix="${work}/prefix"
  root="${work}/orca-v${VERSION}-${os}-${arch}"
  daemon_name="$(daemon_name_for_os "$os")"
  daemon_path="$(daemon_artifact_path "$os" "$arch")"

  rm -rf "$work"
  mkdir -p "$prefix" "$root/bin"

  "$(dirname "$0")/zig" build install-orca \
    -Dtarget="$zig_target" \
    -Doptimize="$ZIG_OPTIMIZE" \
    -Dversion="$VERSION" \
    -Dcommit="$COMMIT" \
    -Dbuild-date="$BUILD_DATE" \
    --prefix "$prefix"

  copy_cli_payload "$root"
  write_release_readme "$root" "orca"
  if [ -f "$prefix/bin/$bin_name" ]; then
    cp "$prefix/bin/$bin_name" "$root/bin/$bin_name"
  elif [ "$os" = "windows" ] && [ -f "$prefix/bin/orca.exe" ]; then
    cp "$prefix/bin/orca.exe" "$root/bin/orca.exe"
  elif [ -f "$prefix/bin/orca" ]; then
    cp "$prefix/bin/orca" "$root/bin/orca"
  else
    printf 'missing Orca binary in %s\n' "$prefix/bin" >&2
    exit 1
  fi
  if [ "$os" != "windows" ] && [ -f "$prefix/bin/orca" ]; then
    cp "$prefix/bin/orca" "$root/bin/orca"
  fi
  if [ "$os" = "windows" ] && [ -f "$prefix/bin/orca.exe" ]; then
    cp "$prefix/bin/orca.exe" "$root/bin/orca.exe"
  fi
  verify_daemon_binary_target "$os" "$arch" "$daemon_path"
  cp -p "$daemon_path" "$root/bin/$daemon_name"
  if [ "$os" != "windows" ]; then
    chmod 0755 "$root/bin/$daemon_name"
  fi
  find "$root" -name .DS_Store -delete

  if [ "$ext" = "zip" ]; then
    (cd "$work" && zip -qr "../../$artifact" "orca-v${VERSION}-${os}-${arch}")
  else
    # COPYFILE_DISABLE=1 prevents macOS bsdtar from embedding extended attributes
    # (LIBARCHIVE.xattr.com.apple.provenance etc.) as PAX headers. This eliminates
    # the 80–120+ "Ignoring unknown extended header keyword" lines on Linux extracts
    # of mac-built release tarballs (Ubuntu 24.04 + Alpine curl|sh flow).
    COPYFILE_DISABLE=1 tar -C "$work" -czf "${DIST_DIR}/$artifact" "orca-v${VERSION}-${os}-${arch}"
  fi
  printf 'Built %s\n' "${DIST_DIR}/$artifact"
}

write_release_manifest() {
  output="${DIST_DIR}/release-manifest.json"
  artifact_entries=""
  first=1
  for file in "${DIST_DIR}"/orca-v*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    hash="$(awk -v name="$name" '$2 == name {print $1}' "${DIST_DIR}/checksums.txt")"
    [ -n "$hash" ] || {
      printf 'missing checksum for %s\n' "$name" >&2
      exit 1
    }
    if [ "$first" = "1" ]; then
      first=0
    else
      artifact_entries="${artifact_entries},"
    fi
    artifact_entries="${artifact_entries}
    {\"name\":\"${name}\",\"sha256\":\"${hash}\"}"
  done

  products_json="[\"orca\", \"orca-daemon\", \"core\"]"
  runtime_assets_json="[\"schemas\", \"policies\", \"fixtures\", \"examples\", \"integrations\", \"packaging\"]"
  schemas_json="[\"schemas/policy-v1.json\", \"schemas/event-v1.json\", \"schemas/mcp-manifest-v1.json\"]"
  fixtures_json="[\"fixtures/shell-abuse/curl-pipe-sh\", \"examples/mcp\", \"examples/network\", \"examples/policies\"]"
  docs_json="[\"README.md\", \"docs/install.md\", \"README-release.md\"]"
  target_platforms="$(target_platforms_json)"
  safety_summary="Orca is a local CLI/runtime firewall; Edge artifacts are not included in CLI-only releases."

  cat >"$output" <<EOF
{
  "release_version": "${VERSION}",
  "commit": "${COMMIT}",
  "build_date": "${BUILD_DATE}",
  "release_channel": "stable",
  "products_included": ${products_json},
  "artifacts": [${artifact_entries}
  ],
  "checksums": "checksums.txt",
  "target_platforms": ${target_platforms},
  "required_runtime_assets": ${runtime_assets_json},
  "schemas_included": ${schemas_json},
  "fixtures_included": ${fixtures_json},
  "docs_included": ${docs_json},
  "safety_boundary_summary": "${safety_summary}",
  "known_limitations_path": null,
  "generated_by": "scripts/build-release.sh",
  "signing_status": "${SIGNING_STATUS}",
  "sbom_status": "hook-only inventory generated at sbom.json"
}
EOF
  printf 'Wrote %s\n' "$output"
}

cleanup_attempts=0
while [ -d "$DIST_DIR" ] && [ "$cleanup_attempts" -lt 5 ]; do
  find "$DIST_DIR" -name .DS_Store -type f -delete 2>/dev/null || true
  rm -rf "$DIST_DIR" 2>/dev/null || true
  cleanup_attempts=$((cleanup_attempts + 1))
  [ ! -d "$DIST_DIR" ] || sleep 1
done
[ ! -d "$DIST_DIR" ] || {
  printf 'could not clean release directory: %s\n' "$DIST_DIR" >&2
  exit 1
}
mkdir -p "$DIST_DIR"

printf '%s\n' "$(selected_targets)" | while read -r os arch zig_target ext bin_name; do
  [ -n "${os:-}" ] || continue
  build_cli_target "$os" "$arch" "$zig_target" "$ext" "$bin_name"
done

if [ "${ORCA_SIGNING_ENABLED:-0}" = "1" ]; then
  if [ -n "${ORCA_SIGNING_COMMAND:-}" ]; then
    SIGNING_STATUS="signed"
    sh -c "$ORCA_SIGNING_COMMAND" sh "$DIST_DIR"
  else
    printf 'Signing requested but ORCA_SIGNING_COMMAND is not set.\n' >&2
    exit 1
  fi
else
  SIGNING_STATUS="signing hook available; not configured"
  printf 'Signing skipped; set ORCA_SIGNING_ENABLED=1 and ORCA_SIGNING_COMMAND in release environments.\n'
fi

./scripts/generate-checksums.sh "$DIST_DIR"
if [ "$RELEASE_PRODUCT" != "host" ]; then
  ORCA_DIST_DIR="$DIST_DIR" ./scripts/render-package-manifests.sh
fi
ORCA_RELEASE_PRODUCT="$RELEASE_PRODUCT" ./scripts/generate-sbom.sh "$DIST_DIR"

write_release_manifest
rm -rf "$DIST_DIR/work"
rm -rf "$DIST_DIR/daemon-artifacts"
