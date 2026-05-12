#!/usr/bin/env sh
set -eu

ARTIFACT_DIR="${1:-dist}"
VERSION="${AEGIS_VERSION:-${ORCA_VERSION:-1.1.0}}"
OUTPUT="${ARTIFACT_DIR}/sbom.json"

# SBOM inventory is emitted alongside checksum-verified release artifacts.
mkdir -p "$ARTIFACT_DIR"

cat > "$OUTPUT" <<EOF
{
  "sbom_format": "aegis-release-inventory",
  "name": "aegis",
  "version": "$VERSION",
  "generator": "scripts/generate-sbom.sh",
  "status": "hook-only",
  "note": "This is a deterministic Phase 41 dependency, target, and runtime asset inventory. Replace with CycloneDX/SPDX output in release environments when an SBOM tool is available; do not claim a complete third-party SBOM from this hook-only file.",
  "components": [
    {"name": "aegis-cli", "type": "application", "language": "zig", "dependencies": []},
    {"name": "aegis-core", "type": "library", "language": "zig", "dependencies": []},
    {"name": "aegis-edge", "type": "application", "language": "zig", "dependencies": []}
  ],
  "build_targets": [
    "darwin-amd64",
    "darwin-arm64",
    "linux-amd64",
    "linux-arm64",
    "windows-amd64",
    "aegis-edge-linux-amd64",
    "aegis-edge-linux-arm64"
  ],
  "runtime_assets": [
    "schemas",
    "policies",
    "examples/edge",
    "docs/edge",
    "customer_pilot",
    "packaging/aegis-edge"
  ],
  "safety_boundary": "Aegis Edge assets are for simulation/SITL/customer-evaluation and bench-preparation only; not real-flight readiness, certification, detect-and-avoid, or autopilot replacement."
}
EOF

printf 'Wrote %s\n' "$OUTPUT"
