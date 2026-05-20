#!/usr/bin/env sh
set -eu

ARTIFACT_DIR="${1:-dist}"
VERSION="${ORCA_VERSION:-$(cat VERSION 2>/dev/null || printf 1.1.0)}"
RELEASE_PRODUCT="${ORCA_RELEASE_PRODUCT:-all}"
OUTPUT="${ARTIFACT_DIR}/sbom.json"

# SBOM inventory is emitted alongside checksum-verified release artifacts.
mkdir -p "$ARTIFACT_DIR"

if [ "$RELEASE_PRODUCT" = "cli" ]; then
  sbom_name="orca-core"
  sbom_format="orca-core-release-inventory"
  components='[
    {"name": "orca", "type": "application", "language": "zig", "dependencies": []},
    {"name": "core", "type": "library", "language": "zig", "dependencies": []}
  ]'
  build_targets='[
    "darwin-amd64",
    "darwin-arm64",
    "linux-amd64",
    "linux-arm64",
    "windows-amd64"
  ]'
  runtime_assets='[
    "schemas",
    "policies",
    "examples",
    "integrations",
    "packaging"
  ]'
  safety_boundary="Orca assets cover local CLI/runtime guardrails only; no hosted telemetry or cloud enforcement is included."
elif [ "$RELEASE_PRODUCT" = "all" ]; then
  sbom_name="orca-core-edge"
  sbom_format="orca-core-edge-release-inventory"
  components='[
    {"name": "orca", "type": "application", "language": "zig", "dependencies": []},
    {"name": "core", "type": "library", "language": "zig", "dependencies": []},
    {"name": "edge", "type": "application", "language": "zig", "dependencies": []}
  ]'
  build_targets='[
    "darwin-amd64",
    "darwin-arm64",
    "linux-amd64",
    "linux-arm64",
    "windows-amd64",
    "edge-linux-amd64",
    "edge-linux-arm64"
  ]'
  runtime_assets='[
    "schemas",
    "policies",
    "examples/edge",
    "docs/edge",
    "customer_pilot",
    "packaging/edge"
  ]'
  safety_boundary="Edge assets are for simulation/SITL/customer-evaluation and bench-preparation only; not real-flight readiness, certification, detect-and-avoid, or autopilot replacement."
else
  printf 'generate-sbom: unsupported ORCA_RELEASE_PRODUCT=%s\n' "$RELEASE_PRODUCT" >&2
  exit 1
fi

cat > "$OUTPUT" <<EOF
{
  "sbom_format": "$sbom_format",
  "name": "$sbom_name",
  "version": "$VERSION",
  "generator": "scripts/generate-sbom.sh",
  "status": "hook-only",
  "note": "This is a deterministic Phase 41 dependency, target, and runtime asset inventory. Replace with CycloneDX/SPDX output in release environments when an SBOM tool is available; do not claim a complete third-party SBOM from this hook-only file.",
  "components": $components,
  "build_targets": $build_targets,
  "runtime_assets": $runtime_assets,
  "safety_boundary": "$safety_boundary"
}
EOF

printf 'Wrote %s\n' "$OUTPUT"
