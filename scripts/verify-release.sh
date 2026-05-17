#!/usr/bin/env sh
set -eu

DIST_DIR="${1:-${ORCA_DIST_DIR:-dist}}"

fail() {
  printf 'release verify: %s\n' "$1" >&2
  exit 1
}

checksum_for_name() {
  name="$1"
  awk -v name="$name" '$2 == name {print $1}' "$DIST_DIR/checksums.txt"
}

require_artifact() {
  pattern="$1"
  found=0
  for artifact in $pattern; do
    [ -f "$artifact" ] || continue
    found=1
    name="$(basename "$artifact")"
    [ -n "$(checksum_for_name "$name")" ] || fail "missing checksum entry for $name"
    grep -q "\"name\":\"$name\"" "$DIST_DIR/release-manifest.json" ||
      fail "missing release-manifest.json artifact entry for $name"
  done
  [ "$found" = "1" ] || fail "missing artifact pattern $pattern"
}

require_orca_archive_binary() {
  pattern="$1"
  binary="$2"
  found=0
  for artifact in $pattern; do
    [ -f "$artifact" ] || continue
    found=1
    name="$(basename "$artifact")"
    case "$name" in
      *.tar.gz)
        tar -tzf "$artifact" | grep -q "^[^/]*/bin/$binary$" ||
          fail "artifact $name missing bin/$binary"
        ;;
      *.zip)
        command -v unzip >/dev/null 2>&1 || fail "unzip is required to inspect $name"
        unzip -Z1 "$artifact" | grep -q "^[^/]*/bin/$binary$" ||
          fail "artifact $name missing bin/$binary"
        ;;
      *)
        fail "unsupported archive format: $name"
        ;;
    esac
  done
  [ "$found" = "1" ] || fail "missing artifact pattern $pattern"
}

disallowed_orca_archive_path() {
  case "$1" in
    */bin/edge|\
    */docs/edge/*|\
    */examples/edge/*|\
    */packages/edge/*|\
    */packaging/edge/*|\
    */schemas/edge-*|\
    */schemas/safety-report*|\
    */customer_pilot/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_orca_archive_excludes() {
  pattern="$1"
  found=0
  for artifact in $pattern; do
    [ -f "$artifact" ] || continue
    found=1
    name="$(basename "$artifact")"
    case "$name" in
      *.tar.gz)
        listing="$(tar -tzf "$artifact")"
        ;;
      *.zip)
        command -v unzip >/dev/null 2>&1 || fail "unzip is required to inspect $name"
        listing="$(unzip -Z1 "$artifact")"
        ;;
      *)
        fail "unsupported archive format: $name"
        ;;
    esac

    for path in $listing; do
      if disallowed_orca_archive_path "$path"; then
        fail "Orca artifact $name contains Edge-only path: $path"
      fi
    done
  done
  [ "$found" = "1" ] || fail "missing artifact pattern $pattern"
}

artifact_package_key() {
  case "$1" in
    orca-v*-darwin-amd64.tar.gz) printf 'darwin-amd64' ;;
    orca-v*-darwin-arm64.tar.gz) printf 'darwin-arm64' ;;
    orca-v*-linux-amd64.tar.gz) printf 'linux-amd64' ;;
    orca-v*-linux-arm64.tar.gz) printf 'linux-arm64' ;;
    orca-v*-windows-amd64.zip) printf 'windows-amd64' ;;
    *) fail "unsupported package artifact name: $1" ;;
  esac
}

artifact_manifest_name() {
  case "$1" in
    orca-v*-darwin-amd64.tar.gz) printf 'orca-v#{version}-darwin-amd64.tar.gz' ;;
    orca-v*-darwin-arm64.tar.gz) printf 'orca-v#{version}-darwin-arm64.tar.gz' ;;
    orca-v*-linux-amd64.tar.gz) printf 'orca-v#{version}-linux-amd64.tar.gz' ;;
    orca-v*-linux-arm64.tar.gz) printf 'orca-v#{version}-linux-arm64.tar.gz' ;;
    *) printf '%s' "$1" ;;
  esac
}

require_manifest_hash_for_artifact() {
  manifest="$1"
  artifact_name="$2"
  hash="$(checksum_for_name "$artifact_name")"
  [ -n "$hash" ] || fail "missing checksum entry for $artifact_name"

  case "$manifest" in
    */homebrew/Formula/orca.rb)
      manifest_name="$(artifact_manifest_name "$artifact_name")"
      awk -v name="$manifest_name" -v hash="$hash" '
        index($0, name) { seen = 1; window = 8 }
        seen && index($0, hash) { ok = 1 }
        seen { window -= 1; if (window <= 0) seen = 0 }
        END { exit ok ? 0 : 1 }
      ' "$manifest" || fail "rendered Homebrew formula checksum is not bound to $artifact_name"
      ;;
    */npm/package.json)
      key="$(artifact_package_key "$artifact_name")"
      grep -Eq "\"$key\"[[:space:]]*:[[:space:]]*\"$hash\"" "$manifest" ||
        fail "rendered npm package checksum is not bound to $artifact_name"
      ;;
    */scoop/orca.json|*/winget/orca.yaml)
      grep -q "$artifact_name" "$manifest" ||
        fail "rendered manifest $(basename "$manifest") missing artifact URL for $artifact_name"
      grep -q "$hash" "$manifest" ||
        fail "rendered manifest $(basename "$manifest") missing checksum for $artifact_name"
      ;;
    *)
      fail "unsupported rendered package manifest: $manifest"
      ;;
  esac
}

require_package_hashes() {
  homebrew="$DIST_DIR/package-manifests/homebrew/Formula/orca.rb"
  npm="$DIST_DIR/package-manifests/npm/package.json"
  scoop="$DIST_DIR/package-manifests/scoop/orca.json"
  winget="$DIST_DIR/package-manifests/winget/orca.yaml"

  for artifact in \
    "$DIST_DIR"/orca-v*-darwin-amd64.tar.gz \
    "$DIST_DIR"/orca-v*-darwin-arm64.tar.gz \
    "$DIST_DIR"/orca-v*-linux-amd64.tar.gz \
    "$DIST_DIR"/orca-v*-linux-arm64.tar.gz
  do
    [ -f "$artifact" ] || continue
    name="$(basename "$artifact")"
    require_manifest_hash_for_artifact "$homebrew" "$name"
    require_manifest_hash_for_artifact "$npm" "$name"
  done
  for artifact in "$DIST_DIR"/orca-v*-windows-amd64.zip; do
    [ -f "$artifact" ] || continue
    name="$(basename "$artifact")"
    require_manifest_hash_for_artifact "$npm" "$name"
    require_manifest_hash_for_artifact "$scoop" "$name"
    require_manifest_hash_for_artifact "$winget" "$name"
  done
}

require_edge_artifacts=0

[ -d "$DIST_DIR" ] || fail "missing dist dir: $DIST_DIR"
[ -s "$DIST_DIR/checksums.txt" ] || fail "missing checksums.txt"
[ -s "$DIST_DIR/release-manifest.json" ] || fail "missing release-manifest.json"
[ -s "$DIST_DIR/sbom.json" ] || fail "missing sbom.json"
[ -s "$DIST_DIR/package-manifests/homebrew/Formula/orca.rb" ] || fail "missing rendered Homebrew formula"
[ -s "$DIST_DIR/package-manifests/npm/package.json" ] || fail "missing rendered npm package manifest"
[ -s "$DIST_DIR/package-manifests/npm/bin/orca.js" ] || fail "missing rendered npm launcher"
[ -s "$DIST_DIR/package-manifests/scoop/orca.json" ] || fail "missing rendered Scoop manifest"
[ -s "$DIST_DIR/package-manifests/winget/orca.yaml" ] || fail "missing rendered WinGet manifest"
grep -q '"products_included"' "$DIST_DIR/release-manifest.json" || fail "release-manifest.json missing products_included"
grep -q '"orca"' "$DIST_DIR/release-manifest.json" || fail "release-manifest.json missing Orca product"
if grep -q '"products_included"[[:space:]]*:[^]]*"edge"' "$DIST_DIR/release-manifest.json"; then
  require_edge_artifacts=1
fi

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$DIST_DIR" && sha256sum -c checksums.txt)
else
  (cd "$DIST_DIR" && shasum -a 256 -c checksums.txt)
fi

require_artifact "$DIST_DIR/orca-v*-darwin-amd64.tar.gz"
require_artifact "$DIST_DIR/orca-v*-darwin-arm64.tar.gz"
require_artifact "$DIST_DIR/orca-v*-linux-amd64.tar.gz"
require_artifact "$DIST_DIR/orca-v*-linux-arm64.tar.gz"
require_artifact "$DIST_DIR/orca-v*-windows-amd64.zip"
require_orca_archive_binary "$DIST_DIR/orca-v*-darwin-amd64.tar.gz" "orca"
require_orca_archive_binary "$DIST_DIR/orca-v*-darwin-arm64.tar.gz" "orca"
require_orca_archive_binary "$DIST_DIR/orca-v*-linux-amd64.tar.gz" "orca"
require_orca_archive_binary "$DIST_DIR/orca-v*-linux-arm64.tar.gz" "orca"
require_orca_archive_binary "$DIST_DIR/orca-v*-windows-amd64.zip" "orca.exe"
require_orca_archive_excludes "$DIST_DIR/orca-v*-darwin-amd64.tar.gz"
require_orca_archive_excludes "$DIST_DIR/orca-v*-darwin-arm64.tar.gz"
require_orca_archive_excludes "$DIST_DIR/orca-v*-linux-amd64.tar.gz"
require_orca_archive_excludes "$DIST_DIR/orca-v*-linux-arm64.tar.gz"
require_orca_archive_excludes "$DIST_DIR/orca-v*-windows-amd64.zip"
if [ "$require_edge_artifacts" = "1" ]; then
  require_artifact "$DIST_DIR/edge-v*-linux-amd64.tar.gz"
  require_artifact "$DIST_DIR/edge-v*-linux-arm64.tar.gz"
fi

if [ "$require_edge_artifacts" = "1" ]; then
  grep -q "not real-flight readiness" "$DIST_DIR/release-manifest.json"
fi
grep -q '"signing_status"' "$DIST_DIR/release-manifest.json"
grep -q '"sbom_status"' "$DIST_DIR/release-manifest.json"
for rendered in \
  "$DIST_DIR/package-manifests/homebrew/Formula/orca.rb" \
  "$DIST_DIR/package-manifests/npm/package.json" \
  "$DIST_DIR/package-manifests/scoop/orca.json" \
  "$DIST_DIR/package-manifests/winget/orca.yaml"
do
  ! grep -q 'PLACEHOLDER' "$rendered" || { printf 'release verify: placeholder left in %s\n' "$rendered" >&2; exit 1; }
done
require_package_hashes

printf 'release verify: passed\n'
if [ "$require_edge_artifacts" = "1" ]; then
  printf 'Limitations: Edge release assets are simulation/SITL/customer-evaluation and bench-preparation only; no real hardware, hosted telemetry, certification, detect-and-avoid, or autopilot replacement.\n'
else
  printf 'Limitations: Orca release assets cover local CLI/runtime guardrails only; no hosted telemetry or cloud enforcement is included.\n'
fi
