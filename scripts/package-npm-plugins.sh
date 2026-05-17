#!/usr/bin/env sh
set -eu

DIST_DIR="${ORCA_DIST_DIR:-dist/npm}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PACKAGES="
opencode-plugin:orca-opencode-plugin
openclaw-plugin:orca-openclaw-plugin
"

rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

CHECKSUMS_FILE="${DIST_DIR}/orca-npm-plugin-checksums.txt"
: > "${CHECKSUMS_FILE}"

TOTAL_ISSUES=0

for entry in ${PACKAGES}; do
  PKG_DIR_NAME="$(echo "$entry" | cut -d: -f1)"
  OUTPUT_PREFIX="$(echo "$entry" | cut -d: -f2)"
  PACKAGE_DIR="${REPO_ROOT}/integrations/${PKG_DIR_NAME}"

  if [ ! -d "${PACKAGE_DIR}" ]; then
    echo "WARNING: Package directory not found: ${PACKAGE_DIR}" >&2
    continue
  fi

  VERSION="$(node -p "require('${PACKAGE_DIR}/package.json').version")"

  echo ""
  echo "========================================"
  echo "Packaging ${OUTPUT_PREFIX} v${VERSION}..."
  echo "========================================"

  if [ ! -f "${PACKAGE_DIR}/dist/index.js" ]; then
    echo "ERROR: dist/index.js not found in ${PACKAGE_DIR}. Run 'npm run build' first." >&2
    exit 1
  fi

  (cd "${PACKAGE_DIR}" && npm pack --dry-run)

  PKG_TARBALL="${DIST_DIR}/${OUTPUT_PREFIX}-v${VERSION}.tgz"
  (cd "${PACKAGE_DIR}" && npm pack --pack-destination "${REPO_ROOT}/${DIST_DIR}")

  BUILT_TARBALL="${DIST_DIR}/${OUTPUT_PREFIX}-${VERSION}.tgz"
  if [ -f "${BUILT_TARBALL}" ]; then
    mv "${BUILT_TARBALL}" "${PKG_TARBALL}"
  fi

  if [ ! -f "${PKG_TARBALL}" ]; then
    echo "ERROR: Failed to create tarball for ${OUTPUT_PREFIX}" >&2
    exit 1
  fi

  echo "Created ${PKG_TARBALL}"

  if command -v sha256sum >/dev/null 2>&1; then
    hash="$(sha256sum "${PKG_TARBALL}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    hash="$(shasum -a 256 "${PKG_TARBALL}" | awk '{print $1}')"
  else
    echo "ERROR: sha256sum or shasum is required" >&2
    exit 1
  fi
  printf '%s  %s\n' "$hash" "$(basename "$PKG_TARBALL")" >> "${CHECKSUMS_FILE}"

  echo "Scanning ${OUTPUT_PREFIX} tarball for potential secrets..."
  SCAN_ISSUES=0

  tmpdir="$(mktemp -d)"
  tar -xzf "${PKG_TARBALL}" -C "$tmpdir"
  if grep -riE "(api_key|apikey|secret|token|password|private_key|privkey)[[:space:]]*[:=][[:space:]]*[\"']?[a-zA-Z0-9_/-]{16,}" "$tmpdir" 2>/dev/null | grep -v "fake_" | grep -v "example" | grep -v "placeholder" | grep -v "your_"; then
    echo "WARNING: Potential secret pattern in ${OUTPUT_PREFIX} tarball" >&2
    SCAN_ISSUES=$((SCAN_ISSUES + 1))
  fi
  rm -rf "$tmpdir"

  if [ "$SCAN_ISSUES" -eq 0 ]; then
    echo "Secret scan passed for ${OUTPUT_PREFIX}."
  else
    echo "WARNING: Secret scan found ${SCAN_ISSUES} potential issues in ${OUTPUT_PREFIX}. Review before release." >&2
    TOTAL_ISSUES=$((TOTAL_ISSUES + SCAN_ISSUES))
  fi
done

echo ""
echo "========================================"
echo "NPM packaging complete. Artifacts in ${DIST_DIR}:"
echo "========================================"
ls -la "${DIST_DIR}"
echo ""
echo "Checksums:"
cat "${CHECKSUMS_FILE}"

if [ "$TOTAL_ISSUES" -eq 0 ]; then
  echo ""
  echo "All secret scans passed."
else
  echo ""
  echo "Total secret scan issues: ${TOTAL_ISSUES}. Failing release packaging." >&2
  exit 1
fi
