# Phase 19 Release Checklist

## Release Artifacts

Expected artifact names:

- `aegis-vX.Y.Z-darwin-amd64.tar.gz`
- `aegis-vX.Y.Z-darwin-arm64.tar.gz`
- `aegis-vX.Y.Z-linux-amd64.tar.gz`
- `aegis-vX.Y.Z-linux-arm64.tar.gz`
- `aegis-vX.Y.Z-windows-amd64.zip`
- `checksums.txt`
- `sbom.json`

Build locally:

```bash
AEGIS_VERSION=1.1.0 ./scripts/build-release.sh
shasum -a 256 -c dist/checksums.txt
```

## Manual Install Verification

Download the matching archive and `checksums.txt`, then verify before extracting:

```bash
shasum -a 256 -c checksums.txt
tar -xzf aegis-vX.Y.Z-linux-amd64.tar.gz
./aegis-vX.Y.Z-linux-amd64/bin/aegis version --json
```

The installer scripts support verified local artifacts:

```bash
AEGIS_VERSION=1.1.0 AEGIS_ARTIFACT_DIR=dist ./scripts/install.sh
```

Do not document blind `curl | sh` installation as the only path. Any remote installer example must also show the checksum verification alternative above.

## Required Checks

- `zig build`
- `zig build test`
- `./zig-out/bin/aegis redteam --ci`
- `./zig-out/bin/aegis version`
- `./zig-out/bin/aegis version --json`
- `for policy in policies/presets/*.yaml; do ./zig-out/bin/aegis policy check "$policy"; done`
- Package metadata syntax checks from `.github/workflows/test.yml`
- `scripts/generate-checksums.sh dist`
- `scripts/generate-sbom.sh dist`

## Signing Status

Signing is hook-only in Phase 19. Normal development and CI must not require signing material.

Release environments may set:

```bash
AEGIS_SIGNING_ENABLED=1
AEGIS_SIGNING_COMMAND='./your-signing-command dist'
```

Do not claim notarized or signed artifacts unless the release job actually signs them and publishes the evidence.

## SBOM Status

`scripts/generate-sbom.sh` writes `sbom.json` as a Phase 19 hook. If a CycloneDX or SPDX generator is available in the release environment, replace the placeholder output during release and keep `checksums.txt` in sync.

## Security Notes

- Install scripts do not collect telemetry.
- Install scripts verify `checksums.txt` before extraction and installation where SHA-256 tooling is available.
- Install scripts refuse unsupported OS/architecture combinations.
- Install scripts refuse to overwrite an unrelated existing file unless explicitly forced.
- Package templates contain release version metadata and placeholder checksums for release automation.
- Public distribution is blocked until the project owner records the final license in `LICENSE`.
- Workflows do not print signing material and do not require signing for normal builds.
