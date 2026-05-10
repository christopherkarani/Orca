#!/usr/bin/env sh
set -eu

VERSION="${ORCA_PLUGIN_VERSION:-${ORCA_VERSION:-1.1.0}}"
DIST_DIR="${ORCA_DIST_DIR:-dist/npm}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${REPO_ROOT}/integrations/opencode-plugin"

echo "Packaging @orca/opencode-plugin v${VERSION}..."

if [ ! -d "${PACKAGE_DIR}" ]; then
  echo "ERROR: Package directory not found: ${PACKAGE_DIR}" >&2
  exit 1
fi

if [ ! -f "${PACKAGE_DIR}/dist/index.js" ]; then
  echo "ERROR: dist/index.js not found. Run 'npm run build' in ${PACKAGE_DIR} first." >&2
  exit 1
fi

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# Create the npm tarball
PKG_TARBALL="${DIST_DIR}/orca-opencode-plugin-v${VERSION}.tgz"
(cd "${PACKAGE_DIR}" && npm pack --dry-run)
(cd "${PACKAGE_DIR}" && npm pack --pack-destination "${REPO_ROOT}/${DIST_DIR}")

# Rename to consistent naming
BUILT_TARBALL="${DIST_DIR}/orca-opencode-plugin-${VERSION}.tgz"
if [ -f "${BUILT_TARBALL}" ]; then
  mv "${BUILT_TARBALL}" "${PKG_TARBALL}"
fi

if [ ! -f "${PKG_TARBALL}" ]; then
  echo "ERROR: Failed to create tarball" >&2
  exit 1
fi

echo "Created ${PKG_TARBALL}"

# Generate checksum
echo "Generating checksum..."
CHECKSUMS_FILE="${DIST_DIR}/orca-npm-plugin-checksums.txt"
if command -v sha256sum >/dev/null 2>&1; then
  hash="$(sha256sum "${PKG_TARBALL}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  hash="$(shasum -a 256 "${PKG_TARBALL}" | awk '{print $1}')"
else
  echo "ERROR: sha256sum or shasum is required" >&2
  exit 1
fi
printf '%s  %s\n' "$hash" "$(basename "$PKG_TARBALL")" > "$CHECKSUMS_FILE"
echo "Created ${CHECKSUMS_FILE}"

# Verify no secrets in tarball
echo "Scanning tarball for potential secrets..."
SECRET_PATTERNS="password|secret|token|api_key|apikey|private_key|privkey|aws_access|aws_secret|github_token|gcp_key|azure_key"
SCAN_ISSUES=0

tmpdir="$(mktemp -d)"
tar -xzf "${PKG_TARBALL}" -C "$tmpdir"
if grep -riE "(api_key|apikey|secret|token|password|private_key|privkey)[[:space:]]*[:=][[:space:]]*[\"']?[a-zA-Z0-9_/-]{16,}" "$tmpdir" 2>/dev/null | grep -v "fake_" | grep -v "example" | grep -v "placeholder" | grep -v "your_"; then
  echo "WARNING: Potential secret pattern in tarball" >&2
  SCAN_ISSUES=$((SCAN_ISSUES + 1))
fi
rm -rf "$tmpdir"

if [ "$SCAN_ISSUES" -eq 0 ]; then
  echo "Secret scan passed."
else
  echo "WARNING: Secret scan found ${SCAN_ISSUES} potential issues. Review before release." >&2
fi

echo ""
echo "NPM packaging complete. Artifact in ${DIST_DIR}:"
ls -la "${DIST_DIR}"
echo ""
cat "${CHECKSUMS_FILE}"
