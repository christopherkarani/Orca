#!/usr/bin/env sh
set -eu

VERSION="${AEGIS_VERSION:-${ORCA_VERSION:-1.1.0}}"
COMMIT="${AEGIS_COMMIT:-${ORCA_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || printf unknown)}}"
BUILD_DATE="${AEGIS_BUILD_DATE:-${ORCA_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}}"
DIST_DIR="${AEGIS_DIST_DIR:-${ORCA_DIST_DIR:-dist}}"
ZIG_OPTIMIZE="${AEGIS_ZIG_OPTIMIZE:-${ORCA_ZIG_OPTIMIZE:-ReleaseSafe}}"
SIGNING_STATUS="not_configured"

# Phase 41 artifact contract:
# - aegis-v1.1.0-darwin-amd64.tar.gz
# - aegis-v1.1.0-darwin-arm64.tar.gz
# - aegis-v1.1.0-linux-amd64.tar.gz
# - aegis-v1.1.0-linux-arm64.tar.gz
# - aegis-v1.1.0-windows-amd64.zip
# - aegis-edge-v1.1.0-linux-amd64.tar.gz
# - aegis-edge-v1.1.0-linux-arm64.tar.gz
# Compatibility binary names orca/orca-edge may be included inside archives,
# but release archive names and checksum entries use Aegis names.

CLI_TARGETS="
darwin amd64 x86_64-macos tar.gz aegis
darwin arm64 aarch64-macos tar.gz aegis
linux amd64 x86_64-linux tar.gz aegis
linux arm64 aarch64-linux tar.gz aegis
windows amd64 x86_64-windows zip aegis.exe
"

EDGE_TARGETS="
linux amd64 x86_64-linux tar.gz aegis-edge
linux arm64 aarch64-linux tar.gz aegis-edge
"

copy_common_payload() {
  root="$1"
  mkdir -p "$root"
  cp README.md LICENSE SECURITY.md CONTRIBUTING.md "$root/"
  cp -R docs policies schemas examples packages packaging scripts customer_pilot "$root/"
  rm -rf "$root"/.DS_Store "$root"/docs/.DS_Store "$root"/packages/.DS_Store "$root"/examples/.DS_Store 2>/dev/null || true
}

write_release_readme() {
  root="$1"
  cat > "$root/README-release.md" <<EOF
# Aegis ${VERSION} Release Artifact

This artifact is built from commit ${COMMIT} at ${BUILD_DATE}.

Verify the archive against the top-level checksums.txt before installing:

\`\`\`sh
sha256sum -c checksums.txt
\`\`\`

Aegis Edge materials in this release are for simulation/SITL/customer-evaluation and bench-preparation only. They are not real-flight readiness, certification, detect-and-avoid, or autopilot replacement.
EOF
}

write_known_limitations() {
  root="$1"
  cp docs/edge/known-limitations.md "$root/known-limitations.md"
}

build_cli_target() {
  os="$1"
  arch="$2"
  zig_target="$3"
  ext="$4"
  bin_name="$5"

  artifact="aegis-v${VERSION}-${os}-${arch}.${ext}"
  work="${DIST_DIR}/work/cli-${os}-${arch}"
  prefix="${work}/prefix"
  root="${work}/aegis-v${VERSION}-${os}-${arch}"

  rm -rf "$work"
  mkdir -p "$prefix" "$root/bin"

  zig build \
    -Dtarget="$zig_target" \
    -Doptimize="$ZIG_OPTIMIZE" \
    -Dversion="$VERSION" \
    -Dcommit="$COMMIT" \
    -Dbuild-date="$BUILD_DATE" \
    --prefix "$prefix"

  copy_common_payload "$root"
  write_release_readme "$root"
  write_known_limitations "$root"
  if [ -f "$prefix/bin/$bin_name" ]; then
    cp "$prefix/bin/$bin_name" "$root/bin/$bin_name"
  elif [ "$os" = "windows" ] && [ -f "$prefix/bin/orca.exe" ]; then
    cp "$prefix/bin/orca.exe" "$root/bin/aegis.exe"
  elif [ -f "$prefix/bin/orca" ]; then
    cp "$prefix/bin/orca" "$root/bin/aegis"
  else
    printf 'missing Aegis CLI binary in %s\n' "$prefix/bin" >&2
    exit 1
  fi
  if [ "$os" != "windows" ] && [ -f "$prefix/bin/orca" ]; then
    cp "$prefix/bin/orca" "$root/bin/orca"
  fi
  if [ "$os" = "windows" ] && [ -f "$prefix/bin/orca.exe" ]; then
    cp "$prefix/bin/orca.exe" "$root/bin/orca.exe"
  fi
  find "$root" -name .DS_Store -delete

  if [ "$ext" = "zip" ]; then
    (cd "$work" && zip -qr "../../$artifact" "aegis-v${VERSION}-${os}-${arch}")
  else
    tar -C "$work" -czf "${DIST_DIR}/$artifact" "aegis-v${VERSION}-${os}-${arch}"
  fi
  printf 'Built %s\n' "${DIST_DIR}/$artifact"
}

build_edge_target() {
  os="$1"
  arch="$2"
  zig_target="$3"
  ext="$4"
  bin_name="$5"

  artifact="aegis-edge-v${VERSION}-${os}-${arch}.${ext}"
  work="${DIST_DIR}/work/edge-${os}-${arch}"
  prefix="${work}/prefix"
  root="${work}/aegis-edge-v${VERSION}-${os}-${arch}"

  rm -rf "$work"
  mkdir -p "$prefix" "$root/bin"

  zig build \
    -Dtarget="$zig_target" \
    -Doptimize="$ZIG_OPTIMIZE" \
    -Dversion="$VERSION" \
    -Dcommit="$COMMIT" \
    -Dbuild-date="$BUILD_DATE" \
    --prefix "$prefix"

  cp "$prefix/bin/$bin_name" "$root/bin/aegis-edge"
  cp LICENSE SECURITY.md "$root/"
  mkdir -p "$root/schemas" "$root/examples" "$root/docs" "$root/packages/edge" "$root/packaging"
  cp -R schemas/* "$root/schemas/"
  cp -R examples/edge "$root/examples/edge"
  cp -R docs/edge "$root/docs/edge"
  cp -R customer_pilot "$root/customer_pilot"
  cp packages/edge/README.md "$root/packages/edge/README.md"
  cp -R packaging/aegis-edge "$root/packaging/aegis-edge"
  cp -R packaging/systemd "$root/packaging/systemd"
  write_release_readme "$root"
  write_known_limitations "$root"
  cat > "$root/package-manifest.yaml" <<EOF
package: aegis-edge
version: ${VERSION}
target_arch: ${os}-${arch}
release_channel: stable
binaries:
  - bin/aegis-edge
assets:
  - schemas
  - examples/edge
  - docs/edge
  - customer_pilot
  - packages/edge/README.md
  - packaging/aegis-edge
  - packaging/systemd
checksums: SHA256SUMS
limitations:
  - simulation/SITL/bench-preparation only
  - no real-flight readiness claim
EOF
  find "$root" -name .DS_Store -delete
  (cd "$root" && find . -type f -print | sort | xargs shasum -a 256 > SHA256SUMS)
  tar -C "$work" -czf "${DIST_DIR}/$artifact" "aegis-edge-v${VERSION}-${os}-${arch}"
  printf 'Built %s\n' "${DIST_DIR}/$artifact"
}

write_release_manifest() {
  output="${DIST_DIR}/release-manifest.json"
  artifact_entries=""
  first=1
  for file in "${DIST_DIR}"/aegis-v* "${DIST_DIR}"/aegis-edge-v*; do
    [ -f "$file" ] || continue
    name="$(basename "$file")"
    hash="$(awk -v name="$name" '$2 == name {print $1}' "${DIST_DIR}/checksums.txt")"
    [ -n "$hash" ] || { printf 'missing checksum for %s\n' "$name" >&2; exit 1; }
    if [ "$first" = "1" ]; then
      first=0
    else
      artifact_entries="${artifact_entries},"
    fi
    artifact_entries="${artifact_entries}
    {\"name\":\"${name}\",\"sha256\":\"${hash}\"}"
  done

  cat > "$output" <<EOF
{
  "release_version": "${VERSION}",
  "commit": "${COMMIT}",
  "build_date": "${BUILD_DATE}",
  "release_channel": "stable",
  "products_included": ["aegis-cli", "aegis-core", "aegis-edge"],
  "artifacts": [${artifact_entries}
  ],
  "checksums": "checksums.txt",
  "target_platforms": ["darwin-amd64", "darwin-arm64", "linux-amd64", "linux-arm64", "windows-amd64"],
  "required_runtime_assets": ["schemas", "policies", "examples/edge", "docs/edge", "customer_pilot", "packaging/aegis-edge"],
  "schemas_included": ["schemas/edge-policy-v1.json", "schemas/edge-event-v1.json", "schemas/safety-report-v1.json", "schemas/policy-v1.json", "schemas/event-v1.json"],
  "fixtures_included": ["examples/edge/redteam", "examples/edge/demos", "examples/edge/safety-case"],
  "docs_included": ["README.md", "docs/install.md", "docs/edge", "README-release.md", "known-limitations.md"],
  "safety_boundary_summary": "Aegis Edge is simulation/SITL/customer-evaluation and bench-preparation only; it is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement.",
  "known_limitations_path": "known-limitations.md",
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
[ ! -d "$DIST_DIR" ] || { printf 'could not clean release directory: %s\n' "$DIST_DIR" >&2; exit 1; }
mkdir -p "$DIST_DIR"

printf '%s\n' "$CLI_TARGETS" | while read -r os arch zig_target ext bin_name; do
  [ -n "${os:-}" ] || continue
  build_cli_target "$os" "$arch" "$zig_target" "$ext" "$bin_name"
done

printf '%s\n' "$EDGE_TARGETS" | while read -r os arch zig_target ext bin_name; do
  [ -n "${os:-}" ] || continue
  build_edge_target "$os" "$arch" "$zig_target" "$ext" "$bin_name"
done

./scripts/generate-checksums.sh "$DIST_DIR"
./scripts/generate-sbom.sh "$DIST_DIR"

if [ "${AEGIS_SIGNING_ENABLED:-${ORCA_SIGNING_ENABLED:-0}}" = "1" ]; then
  if [ -n "${AEGIS_SIGNING_COMMAND:-${ORCA_SIGNING_COMMAND:-}}" ]; then
    SIGNING_STATUS="signed"
    sh -c "${AEGIS_SIGNING_COMMAND:-${ORCA_SIGNING_COMMAND}}" sh "$DIST_DIR"
  else
    printf 'Signing requested but AEGIS_SIGNING_COMMAND is not set.\n' >&2
    exit 1
  fi
else
  SIGNING_STATUS="signing hook available; not configured"
  printf 'Signing skipped; set AEGIS_SIGNING_ENABLED=1 and AEGIS_SIGNING_COMMAND in release environments.\n'
fi

write_release_manifest
