#!/usr/bin/env sh
set -eu

VERSION="${ORCA_VERSION:-$(cat VERSION 2>/dev/null || printf 1.1.0)}"
COMMIT="${ORCA_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || printf unknown)}"
BUILD_DATE="${ORCA_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
ZIG_OPTIMIZE="${ORCA_ZIG_OPTIMIZE:-ReleaseSafe}"
SIGNING_STATUS="not_configured"

# Phase 41 artifact contract:
# - orca-v1.1.0-darwin-amd64.tar.gz
# - orca-v1.1.0-darwin-arm64.tar.gz
# - orca-v1.1.0-linux-amd64.tar.gz
# - orca-v1.1.0-linux-arm64.tar.gz
# - orca-v1.1.0-windows-amd64.zip

CLI_TARGETS="
darwin amd64 x86_64-macos tar.gz orca
darwin arm64 aarch64-macos tar.gz orca
linux amd64 x86_64-linux tar.gz orca
linux arm64 aarch64-linux tar.gz orca
windows amd64 x86_64-windows zip orca.exe
"

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
        "$root/.DS_Store" \
        "$root/docs/.DS_Store" \
        "$root/packages/.DS_Store" \
        "$root/examples/.DS_Store" \
        "$root/orca-dashboard-ui/node_modules" 2>/dev/null || true
}

write_release_readme() {
    root="$1"
    cat > "$root/README-release.md" <<EOF
# Orca ${VERSION} Release Artifact

This artifact is built from commit ${COMMIT} at ${BUILD_DATE}.

Verify the archive against the top-level checksums.txt before installing:

\`\`\`sh
sha256sum -c checksums.txt
\`\`\`

This archive contains the Orca CLI plus Core policy, audit, replay, redaction, schema, integration, and packaging resources.
EOF
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

    rm -rf "$work"
    mkdir -p "$prefix" "$root/bin"

    zig build install-orca \
        -Dtarget="$zig_target" \
        -Doptimize="$ZIG_OPTIMIZE" \
        -Dcommit="$COMMIT" \
        -Dbuild-date="$BUILD_DATE" \
        --prefix "$prefix"

    copy_cli_payload "$root"
    write_release_readme "$root"
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
    find "$root" -name .DS_Store -delete

    if [ "$ext" = "zip" ]; then
        (cd "$work" && zip -qr "../../$artifact" "orca-v${VERSION}-${os}-${arch}")
    else
        tar -C "$work" -czf "${DIST_DIR}/$artifact" "orca-v${VERSION}-${os}-${arch}"
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
        [ -n "$hash" ] || { printf 'missing checksum for %s\n' "$name" >&2; exit 1; }
        if [ "$first" = "1" ]; then
            first=0
        else
            artifact_entries="${artifact_entries},"
        fi
        artifact_entries="${artifact_entries}
    {\"name\":\"${name}\",\"sha256\":\"${hash}\"}"
    done

    products_json="[\"orca\", \"core\"]"
    runtime_assets_json="[\"schemas\", \"policies\", \"fixtures\", \"examples\", \"integrations\", \"packaging\"]"
    schemas_json="[\"schemas/policy-v1.json\", \"schemas/event-v1.json\", \"schemas/mcp-manifest-v1.json\"]"
    fixtures_json="[\"fixtures/shell-abuse/curl-pipe-sh\", \"examples/mcp\", \"examples/network\", \"examples/policies\"]"
    docs_json="[\"README.md\", \"docs/install.md\", \"README-release.md\"]"
    safety_summary="Orca is a local CLI/runtime firewall for AI agents."

    cat > "$output" <<EOF
{
  "release_version": "${VERSION}",
  "commit": "${COMMIT}",
  "build_date": "${BUILD_DATE}",
  "release_channel": "stable",
  "products_included": ${products_json},
  "artifacts": [${artifact_entries}
  ],
  "checksums": "checksums.txt",
  "target_platforms": ["darwin-amd64", "darwin-arm64", "linux-amd64", "linux-arm64", "windows-amd64"],
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
[ ! -d "$DIST_DIR" ] || { printf 'could not clean release directory: %s\n' "$DIST_DIR" >&2; exit 1; }
mkdir -p "$DIST_DIR"

printf '%s\n' "$CLI_TARGETS" | while read -r os arch zig_target ext bin_name; do
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
ORCA_DIST_DIR="$DIST_DIR" ./scripts/render-package-manifests.sh
ORCA_RELEASE_PRODUCT="cli" ./scripts/generate-sbom.sh "$DIST_DIR"

write_release_manifest
rm -rf "$DIST_DIR/work"
