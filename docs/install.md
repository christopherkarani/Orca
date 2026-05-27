# Install

## Build From Source

```sh
zig version
zig build
./zig-out/bin/orca version --json
```

Use Zig `0.15.2`.

## Release Artifacts

Phase 41 release helpers build checksum-covered Orca and Edge archives into `dist/`:

```sh
./scripts/build-release.sh
(cd dist && shasum -a 256 -c checksums.txt)
```

Windows archive smoke-test helper:

```powershell
.\scripts\build-release.ps1 -ArchiveOnly
.\scripts\install.ps1 -Version 1.1.0 -ArtifactDir .\dist -InstallDir "$env:USERPROFILE\bin"
```

`scripts/build-release.ps1` does not produce `release-manifest.json` or rendered package manifests. Use `scripts/build-release.sh` plus `scripts/verify-release.sh` for production release verification.

Do not use an install-only path without verification. Download the archive, verify `dist/checksums.txt`, inspect the install script if using it, then install.

## Homebrew

Homebrew distribution uses the `christopherkarani/homebrew-orca` tap and the GitHub Release archives from `christopherkarani/Orca`.

Maintainer release flow:

```sh
./scripts/build-release.sh
brew audit --strict --online dist/package-manifests/homebrew/Formula/orca.rb
brew install --build-from-source dist/package-manifests/homebrew/Formula/orca.rb
brew test dist/package-manifests/homebrew/Formula/orca.rb
```

User install after the tap repository is published:

```sh
brew tap christopherkarani/orca
brew install orca
orca plugin install hermes --yes
```

## Manual Artifact Install

1. Download or build the archive for your OS and CPU.
2. Verify its SHA-256 digest against `dist/checksums.txt`.
3. Extract the archive, or run `scripts/install.sh` / `scripts/install.ps1` to install the binary and runtime assets together.
4. Ensure `orca` is on `PATH` and `ORCA_RESOURCE_ROOT` points at the installed runtime tree (`~/.local/share/orca/current` on Unix, `%USERPROFILE%\.orca\share\current` on Windows).
5. Run `orca doctor`.

## Package Templates

Templates exist under `packaging/`:

- Homebrew: `packaging/homebrew/Formula/orca.rb`
- Scoop: `packaging/scoop/orca.json`
- WinGet: `packaging/winget/orca.yaml`
- npm wrapper: `packaging/npm/package.json`
- Docker: `packaging/docker/Dockerfile`

They contain release-time placeholders until artifacts and checksums are generated.

## Edge

Edge install instructions live in [docs/edge/install.md](edge/install.md). Edge artifacts are Linux amd64/arm64 only in this release and must include runtime assets. Edge is fake/SITL/customer-evaluation and bench-preparation only; it is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement.

## macOS Notes

macOS builds provide process supervision, environment filtering, staged writes, PATH/shell shims, MCP stdio proxying, audit/replay, and network policy decisions. Transparent filesystem and transparent network enforcement are limited unless `orca doctor` says otherwise.

## Linux Notes

Linux builds use backend detection for namespace, seccomp, Landlock, cgroup, and process supervision capability. v1.1.0 does not install kernel-backed restrictions as an active strong sandbox.

## Windows Notes

Windows builds use `orca.exe`, PowerShell scripts, path normalization, command wrappers, and process cleanup support where implemented. Transparent filesystem and network enforcement are limited unless `orca doctor` reports active support.
