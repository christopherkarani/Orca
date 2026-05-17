# Release

## Checklist

- Set version metadata.
- Run `zig build`.
- Run `zig build test`.
- Run `./zig-out/bin/orca redteam --ci`.
- Run `./zig-out/bin/orca doctor`.
- Build production artifacts with `scripts/build-release.sh`.
- Generate checksums with `scripts/generate-checksums.sh`.
- Render package manifests with `scripts/render-package-manifests.sh`.
- Generate SBOM hook output with `scripts/generate-sbom.sh`.
- Update the Homebrew formula with `scripts/update-homebrew-formula.sh`.
- Verify install docs and package templates.
- Confirm no docs or artifacts contain raw synthetic secrets.

## Artifacts

Release archives are expected under `dist/`. Checksums live in `dist/checksums.txt`. Publishable package-manager manifests are rendered under `dist/package-manifests/`.

`scripts/build-release.ps1 -ArchiveOnly` is a Windows archive smoke-test helper. It is fail-closed for production because it does not emit `release-manifest.json` or rendered package manifests.

## Signing And SBOM

Signing is optional through `ORCA_SIGNING_ENABLED=1` and `ORCA_SIGNING_COMMAND`. The SBOM hook writes `dist/sbom.json`.

## Package Templates

Source templates remain fail-closed while they contain placeholder checksums. Render Homebrew, Scoop, WinGet, and npm manifests from generated artifact names and checksums before publishing. The Homebrew tap source is `packaging/homebrew/Formula/orca.rb`.

## Versioning

v1.1.0 release candidates must build with `version` metadata set to `1.1.0` and pass the production readiness gates in `PRODUCTION_READINESS_GATES.md`.
