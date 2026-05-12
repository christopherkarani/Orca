#!/usr/bin/env sh
set -eu

VERSION="${ORCA_VERSION:-1.1.0}"
COMMIT="${ORCA_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || printf unknown)}"
BUILD_DATE="${ORCA_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DIST_DIR="${ORCA_DIST_DIR:-dist}"
ZIG_OPTIMIZE="${ORCA_ZIG_OPTIMIZE:-ReleaseSafe}"

TARGETS="
darwin amd64 x86_64-macos tar.gz orca
darwin arm64 aarch64-macos tar.gz orca
linux amd64 x86_64-linux tar.gz orca
linux arm64 aarch64-linux tar.gz orca
windows amd64 x86_64-windows zip orca.exe
"

copy_release_payload() {
  root="$1"
  mkdir -p "$root"
  cp README.md LICENSE SECURITY.md CONTRIBUTING.md "$root/"
  cp -R docs policies schemas fixtures examples packages packaging scripts "$root/"
}

build_target() {
  os="$1"
  arch="$2"
  zig_target="$3"
  ext="$4"
  bin_name="$5"

  artifact="orca-v${VERSION}-${os}-${arch}.${ext}"
  work="${DIST_DIR}/work/${os}-${arch}"
  prefix="${work}/prefix"
  root="${work}/orca-v${VERSION}-${os}-${arch}"

  rm -rf "$work"
  mkdir -p "$prefix" "$root"

  zig build \
    -Dtarget="$zig_target" \
    -Doptimize="$ZIG_OPTIMIZE" \
    -Dversion="$VERSION" \
    -Dcommit="$COMMIT" \
    -Dbuild-date="$BUILD_DATE" \
    --prefix "$prefix"

  copy_release_payload "$root"
  mkdir -p "$root/bin"
  cp "$prefix/bin/$bin_name" "$root/bin/$bin_name"
  edge_bin_name="orca-edge"
  if [ "$os" = "windows" ]; then
    edge_bin_name="orca-edge.exe"
  fi
  cp "$prefix/bin/$edge_bin_name" "$root/bin/$edge_bin_name"
  aegis_edge_bin_name="aegis-edge"
  if [ "$os" = "windows" ]; then
    aegis_edge_bin_name="aegis-edge.exe"
  fi
  if [ -f "$prefix/bin/$aegis_edge_bin_name" ]; then
    cp "$prefix/bin/$aegis_edge_bin_name" "$root/bin/$aegis_edge_bin_name"
  fi

  if [ "$ext" = "zip" ]; then
    (cd "$work" && zip -qr "../../$artifact" "orca-v${VERSION}-${os}-${arch}")
  else
    tar -C "$work" -czf "${DIST_DIR}/$artifact" "orca-v${VERSION}-${os}-${arch}"
  fi
  printf 'Built %s\n' "${DIST_DIR}/$artifact"

  if [ "$os" = "linux" ]; then
    edge_artifact="aegis-edge-v${VERSION}-linux-${arch}.tar.gz"
    edge_root="${work}/aegis-edge-v${VERSION}-linux-${arch}"
    mkdir -p "$edge_root/bin" "$edge_root/schemas" "$edge_root/examples" "$edge_root/docs" "$edge_root/packages" "$edge_root/packaging"
    if [ -f "$prefix/bin/aegis-edge" ]; then
      cp "$prefix/bin/aegis-edge" "$edge_root/bin/aegis-edge"
    else
      cp "$prefix/bin/orca-edge" "$edge_root/bin/aegis-edge"
    fi
    cp LICENSE SECURITY.md "$edge_root/"
    cp -R schemas/* "$edge_root/schemas/"
    cp -R examples/edge "$edge_root/examples/edge"
    cp -R docs/edge "$edge_root/docs/edge"
    mkdir -p "$edge_root/packages/edge"
    cp packages/edge/README.md "$edge_root/packages/edge/README.md"
    cp -R packaging/aegis-edge "$edge_root/packaging/aegis-edge"
    cat > "$edge_root/MANIFEST.yaml" <<EOF
package: aegis-edge
version: ${VERSION}
target_arch: linux-${arch}
binaries:
  - bin/aegis-edge
assets:
  - schemas
  - examples/edge
  - docs/edge
  - packages/edge/README.md
limitations:
  - simulation/SITL/bench-preparation only
  - no real-flight readiness claim
EOF
    (cd "$edge_root" && find . -type f -print | sort | xargs shasum -a 256 > SHA256SUMS)
    tar -C "$work" -czf "${DIST_DIR}/$edge_artifact" "aegis-edge-v${VERSION}-linux-${arch}"
    printf 'Built %s\n' "${DIST_DIR}/$edge_artifact"
  fi
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

printf '%s\n' "$TARGETS" | while read -r os arch zig_target ext bin_name; do
  [ -n "${os:-}" ] || continue
  build_target "$os" "$arch" "$zig_target" "$ext" "$bin_name"
done

./scripts/generate-checksums.sh "$DIST_DIR"
./scripts/generate-sbom.sh "$DIST_DIR"

if [ "${ORCA_SIGNING_ENABLED:-0}" = "1" ]; then
  if [ -n "${ORCA_SIGNING_COMMAND:-}" ]; then
    sh -c "$ORCA_SIGNING_COMMAND" sh "$DIST_DIR"
  else
    printf 'Signing requested but ORCA_SIGNING_COMMAND is not set.\n' >&2
    exit 1
  fi
else
  printf 'Signing skipped; set ORCA_SIGNING_ENABLED=1 and ORCA_SIGNING_COMMAND in release environments.\n'
fi
