# Orca Launch Checklist

## Release Information

- **Product**: Orca
- **Version**: 1.1.0
- **Tag**: `v1.1.0`
- **GitHub Release URL**: (to be filled after release creation)

## Pre-Launch

- [x] README updated with Orca branding
- [x] PLUGIN_RELEASE_NOTES.md published
- [x] LAUNCH_PLUGINS.md ready
- [x] SECURITY.md ready
- [x] Issue templates renamed and updated
- [x] Build passes (`zig build`)
- [x] Tests pass (`zig build test`)
- [x] Redteam passes (`orca redteam --ci`)
- [x] Plugin packages generated (`orca-codex-plugin-v1.1.0.zip`, `orca-claude-code-plugin-v1.1.0.zip`)
- [x] Plugin checksums generated (`orca-plugin-checksums.txt`)
- [x] Binary artifacts generated (darwin/linux/windows)
- [x] Binary checksums generated (`dist/checksums.txt`)
- [x] SBOM generated (`dist/sbom.json`)

## Launch

- [x] Tag created: `v1.1.0`
- [x] Tag pushed to origin
- [ ] GitHub release created
- [ ] Artifacts uploaded to GitHub release
- [ ] Checksum file uploaded to GitHub release

## Post-Launch (First 72 Hours)

- **Triage labels**: `bug`, `docs`, `plugin-codex`, `plugin-claude`, `security`
- **First patch branch**: `patch/v1.1.1`
- **Known limitations**:
  - Hooks are advisory and depend on host support.
  - Official marketplace availability is not yet implemented.
  - Plugin installation is preview/dry-run by default.
  - No telemetry is collected.
  - The plugins do not protect sessions that are not launched through Orca.
  - These plugins do not add MCP server functionality or drone-specific plugin features.

## Security Issue Reporting

Report security issues privately through [SECURITY.md](SECURITY.md).
Do not paste real secrets, tokens, credentials, or private keys into public issues.

## Migration from Aegis

Users migrating from Aegis should:
1. Build Orca: `zig build`
2. Use `orca` instead of `aegis` for new commands
3. The `aegis` compatibility alias is available for backward compatibility
4. Config paths (`.aegis/`) remain unchanged

## Links

- [Release Report](docs/release/orca-v1.1.0-release-report.md)
- [Plugin Release Notes](PLUGIN_RELEASE_NOTES.md)
- [Launch Announcement](LAUNCH_PLUGINS.md)
- [Security Policy](SECURITY.md)
- [Contributing Guide](CONTRIBUTING.md)
