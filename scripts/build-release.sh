#!/usr/bin/env sh
set -eu

VERSION="${AEGIS_VERSION:-1.0.0}"
COMMIT="${AEGIS_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || printf unknown)}"
BUILD_DATE="${AEGIS_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DIST_DIR="${AEGIS_DIST_DIR:-dist}"
ZIG_OPTIMIZE="${AEGIS_ZIG_OPTIMIZE:-ReleaseSafe}"

TARGETS="
darwin amd64 x86_64-macos tar.gz aegis
darwin arm64 aarch64-macos tar.gz aegis
linux amd64 x86_64-linux tar.gz aegis
linux arm64 aarch64-linux tar.gz aegis
windows amd64 x86_64-windows zip aegis.exe
"

copy_release_payload() {
  root="$1"
  mkdir -p "$root"
  cp README.md LICENSE SECURITY.md CONTRIBUTING.md "$root/"
  cp -R docs policies schemas fixtures "$root/"
}

build_target() {
  os="$1"
  arch="$2"
  zig_target="$3"
  ext="$4"
  bin_name="$5"

  artifact="aegis-v${VERSION}-${os}-${arch}.${ext}"
  work="${DIST_DIR}/work/${os}-${arch}"
  prefix="${work}/prefix"
  root="${work}/aegis-v${VERSION}-${os}-${arch}"

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

  if [ "$ext" = "zip" ]; then
    (cd "$work" && zip -qr "../../$artifact" "aegis-v${VERSION}-${os}-${arch}")
  else
    tar -C "$work" -czf "${DIST_DIR}/$artifact" "aegis-v${VERSION}-${os}-${arch}"
  fi
  printf 'Built %s\n' "${DIST_DIR}/$artifact"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

printf '%s\n' "$TARGETS" | while read -r os arch zig_target ext bin_name; do
  [ -n "${os:-}" ] || continue
  build_target "$os" "$arch" "$zig_target" "$ext" "$bin_name"
done

./scripts/generate-checksums.sh "$DIST_DIR"
./scripts/generate-sbom.sh "$DIST_DIR"

if [ "${AEGIS_SIGNING_ENABLED:-0}" = "1" ]; then
  if [ -n "${AEGIS_SIGNING_COMMAND:-}" ]; then
    sh -c "$AEGIS_SIGNING_COMMAND" sh "$DIST_DIR"
  else
    printf 'Signing requested but AEGIS_SIGNING_COMMAND is not set.\n' >&2
    exit 1
  fi
else
  printf 'Signing skipped; set AEGIS_SIGNING_ENABLED=1 and AEGIS_SIGNING_COMMAND in release environments.\n'
fi
