# Release

## Checklist

- Set version metadata.
- Run `zig build`.
- Run `zig build test`.
- Run `./zig-out/bin/aegis redteam --ci`.
- Run `./zig-out/bin/aegis doctor`.
- Build artifacts with `scripts/build-release.sh` or `scripts/build-release.ps1`.
- Generate checksums with `scripts/generate-checksums.sh`.
- Generate SBOM hook output with `scripts/generate-sbom.sh`.
- Verify install docs and package templates.
- Confirm no docs or artifacts contain raw synthetic secrets.

## Artifacts

Release archives are expected under `dist/`. Checksums live in `dist/checksums.txt`.

## Signing And SBOM

Signing is optional through `AEGIS_SIGNING_ENABLED=1` and `AEGIS_SIGNING_COMMAND`. The SBOM hook writes `dist/sbom.json`.

## Package Templates

Update Homebrew, Scoop, WinGet, npm, and Docker templates from generated artifact names and checksums.

## Versioning

Aegis is currently pre-1.0. v1.0 requires the production readiness gates in `PRODUCTION_READINESS_GATES.md`.
