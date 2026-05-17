# Phase 19 Release Checklist

## Release Artifacts

Expected artifact names:

- `orca-vX.Y.Z-darwin-amd64.tar.gz`
- `orca-vX.Y.Z-darwin-arm64.tar.gz`
- `orca-vX.Y.Z-linux-amd64.tar.gz`
- `orca-vX.Y.Z-linux-arm64.tar.gz`
- `orca-vX.Y.Z-windows-amd64.zip`
- `checksums.txt`
- `sbom.json`

Build locally:

```bash
ORCA_VERSION=1.1.0 ./scripts/build-cli-release.sh
(cd dist && shasum -a 256 -c checksums.txt)
./scripts/verify-release.sh dist
```

`scripts/build-cli-release.sh` builds the Orca/Core CLI release set above. The broader
`scripts/build-release.sh` defaults to all products and must include the matching Edge
artifacts when the release manifest declares Edge in `products_included`.

## Manual Install Verification

Download the matching archive and `checksums.txt`, then verify before extracting:

```bash
shasum -a 256 -c checksums.txt
tar -xzf orca-vX.Y.Z-linux-amd64.tar.gz
./orca-vX.Y.Z-linux-amd64/bin/orca version --json
```

The installer scripts support verified local artifacts:

```bash
ORCA_VERSION=1.1.0 ORCA_ARTIFACT_DIR=dist ./scripts/install.sh
```

Do not document blind `curl | sh` installation as the only path. Any remote installer example must also show the checksum verification alternative above.

## Required Checks

- `zig build`
- `zig build test`
- `./zig-out/bin/orca redteam --ci`
- `./zig-out/bin/orca version`
- `./zig-out/bin/orca version --json`
- `for policy in policies/presets/*.yaml; do ./zig-out/bin/orca policy check "$policy"; done`
- Package metadata syntax checks from `.github/workflows/test.yml`
- `scripts/generate-checksums.sh dist`
- `ORCA_RELEASE_PRODUCT=cli scripts/generate-sbom.sh dist`
- `scripts/verify-release.sh dist`

## Signing Status

Signing is hook-only in Phase 19. Normal development and CI must not require signing material.

Release environments may set:

```bash
ORCA_SIGNING_ENABLED=1
ORCA_SIGNING_COMMAND='./your-signing-command dist'
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
