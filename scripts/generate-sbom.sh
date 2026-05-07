#!/usr/bin/env sh
set -eu

ARTIFACT_DIR="${1:-dist}"
VERSION="${AEGIS_VERSION:-1.0.0}"
OUTPUT="${ARTIFACT_DIR}/sbom.json"

mkdir -p "$ARTIFACT_DIR"

cat > "$OUTPUT" <<EOF
{
  "sbom_format": "placeholder",
  "name": "aegis",
  "version": "$VERSION",
  "generator": "scripts/generate-sbom.sh",
  "status": "hook-only",
  "note": "Phase 19 provides an SBOM hook. Replace this placeholder with CycloneDX/SPDX output in the release environment if an SBOM tool is available.",
  "components": [
    {
      "name": "aegis",
      "type": "application",
      "language": "zig",
      "dependencies": []
    }
  ]
}
EOF

printf 'Wrote %s\n' "$OUTPUT"
