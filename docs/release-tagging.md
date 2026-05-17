# Release Tagging

## Pre-Tag Checklist

Run:

```sh
zig build
zig build test
./scripts/release-dry-run.sh
```

Confirm `reports/production-readiness-report.md`, `release-checklist.md`, `checksums.txt`, `sbom.json`, and `release-manifest.json` are current.

## Tag

```sh
git status --short
git tag -a v1.1.0 -m "Orca v1.1.0"
git push origin v1.1.0
```

## Build And Verify Artifacts

```sh
ORCA_VERSION=1.1.0 ./scripts/build-release.sh
./scripts/verify-release.sh dist
cd dist && sha256sum -c checksums.txt
```

## Publish

Create a GitHub release using `GITHUB_RELEASE_DRAFT.md` and upload the artifacts, `checksums.txt`, `release-manifest.json`, and `sbom.json`.

## Rollback

If publishing fails before public use, delete the draft release and rebuild from a clean checkout. If a tag must be removed:

```sh
git tag -d v1.1.0
git push origin :refs/tags/v1.1.0
```

Do not include secret tokens in commands. Edge remains not real-flight readiness.
