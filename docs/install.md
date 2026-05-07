# Install

## Build From Source

```sh
zig version
zig build
./zig-out/bin/aegis version --json
```

Use Zig `0.15.2`.

## Release Artifacts

Phase 19 release helpers build archives into `dist/`:

```sh
./scripts/build-release.sh
./scripts/generate-checksums.sh
shasum -a 256 -c dist/checksums.txt
```

Windows templates:

```powershell
.\scripts\build-release.ps1
.\scripts\install.ps1 -Version 1.0.0 -ArtifactDir .\dist -InstallDir "$env:USERPROFILE\bin"
```

Do not use an install-only path without verification. Download the archive, verify `dist/checksums.txt`, inspect the install script if using it, then install.

## Manual Artifact Install

1. Download or build the archive for your OS and CPU.
2. Verify its SHA-256 digest against `dist/checksums.txt`.
3. Extract the archive.
4. Put `aegis` or `aegis.exe` on `PATH`.
5. Run `aegis doctor`.

## Package Templates

Templates exist under `packaging/`:

- Homebrew: `packaging/homebrew/aegis.rb`
- Scoop: `packaging/scoop/aegis.json`
- WinGet: `packaging/winget/aegis.yaml`
- npm wrapper: `packaging/npm/package.json`
- Docker: `packaging/docker/Dockerfile`

They contain release-time placeholders until artifacts and checksums are generated.

## macOS Notes

macOS builds provide process supervision, environment filtering, staged writes, PATH/shell shims, MCP stdio proxying, audit/replay, and network policy decisions. Transparent filesystem and transparent network enforcement are limited unless `aegis doctor` says otherwise.

## Linux Notes

Linux builds use backend detection for namespace, seccomp, Landlock, cgroup, and process supervision capability. v1.0.0 does not install kernel-backed restrictions as an active strong sandbox.

## Windows Notes

Windows builds use `aegis.exe`, PowerShell scripts, path normalization, command wrappers, and process cleanup support where implemented. Transparent filesystem and network enforcement are limited unless `aegis doctor` reports active support.
