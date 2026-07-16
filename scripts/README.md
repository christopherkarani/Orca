# Scripts

Phase 19 release helpers:

- `install.sh`: macOS/Linux installer with OS/arch detection, checksum verification, and a step-based TTY UI (banner, progress phases, activation hero, host soft-detect). Set `ORCA_INSTALL_QUIET=1` for non-error silence; honors `NO_COLOR`.
- `install.ps1`: Windows installer with the same install contracts and a matching presentation.
- `install-orca-plugin.sh`: one-command bootstrap for `orca` + plugin install + plugin doctor (`opencode`, `openclaw`, or `hermes`).
- `install-orca-plugin.ps1`: Windows one-command bootstrap for `orca` + plugin install + plugin doctor (`opencode`, `openclaw`, or `hermes`).
- `update-homebrew-formula.sh`: updates `packaging/homebrew/Formula/orca.rb` from `dist/checksums.txt`.
- `render-package-manifests.sh`: renders publishable Homebrew, npm, Scoop, and WinGet manifests under `dist/package-manifests/` from `dist/checksums.txt`.
- `build-release.sh`: builds cross-platform release archives into `dist/`.
- `build-release.ps1`: PowerShell archive smoke-test helper; pass `-ArchiveOnly`. Production release verification must use `build-release.sh` because the PowerShell helper does not emit `release-manifest.json` or rendered package manifests.
- `generate-checksums.sh`: writes `dist/checksums.txt`.
- `generate-sbom.sh`: writes the Phase 19 `dist/sbom.json` hook output.

Signing is optional and controlled by `ORCA_SIGNING_ENABLED=1` plus `ORCA_SIGNING_COMMAND`.
