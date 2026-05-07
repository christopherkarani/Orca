# Scripts

Phase 19 release helpers:

- `install.sh`: macOS/Linux installer with OS/arch detection and checksum verification.
- `install.ps1`: Windows installer with OS/arch detection and checksum verification.
- `build-release.sh`: builds cross-platform release archives into `dist/`.
- `build-release.ps1`: PowerShell release builder template.
- `generate-checksums.sh`: writes `dist/checksums.txt`.
- `generate-sbom.sh`: writes the Phase 19 `dist/sbom.json` hook output.

Signing is optional and controlled by `AEGIS_SIGNING_ENABLED=1` plus `AEGIS_SIGNING_COMMAND`.
