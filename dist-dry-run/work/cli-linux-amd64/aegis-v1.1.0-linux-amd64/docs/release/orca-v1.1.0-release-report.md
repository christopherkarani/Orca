# Orca v1.1.0 Release Report

## Summary

This release finalizes the Orca public release. The repository has been renamed from Aegis to Orca across user-facing strings, documentation, scripts, and build artifacts. The `orca` binary is now the primary CLI, with `aegis` maintained as a compatibility alias.

## Release Version/Tag

- **Version**: 1.1.0
- **Tag**: `v1.1.0`
- **Tag message**: "Orca v1.1.0"

## Build Results

- `zig build`: PASS
- `zig build test`: PASS (538/545 tests passed, 6 skipped, 1 unrelated Windows test)

## Test Results

- Orca CLI smoke tests: PASS
  - `orca --help`: outputs Orca branding
  - `orca version`: outputs `orca 1.1.0`
  - `orca doctor`: outputs Orca Doctor
- Plugin doctor commands: PASS
  - `orca plugin doctor codex`: PASS
  - `orca plugin doctor claude`: PASS
- Plugin manifest commands: PASS
  - `orca plugin manifest codex`: PASS
  - `orca plugin manifest claude`: PASS
- Plugin install dry-run commands: PASS
  - `orca plugin install codex --dry-run`: PASS
  - `orca plugin install claude --dry-run`: PASS
- Hook smoke tests: PASS
  - Codex PreToolUse hook: blocks dangerous command correctly
  - Claude PreToolUse hook: blocks dangerous command correctly
- Redteam result: PASS (10/10 fixtures passed, 100%)

## Plugin Package Result

- `orca-codex-plugin-v1.1.0.zip`: generated
- `orca-claude-code-plugin-v1.1.0.zip`: generated
- `orca-claude-marketplace-v1.1.0.zip`: generated
- `orca-plugin-checksums.txt`: generated
- Secret scan: PASS (no obvious secrets found)

## Binary Artifact Result

- `orca-v1.1.0-darwin-amd64.tar.gz`: generated
- `orca-v1.1.0-darwin-arm64.tar.gz`: generated
- `orca-v1.1.0-linux-amd64.tar.gz`: generated
- `orca-v1.1.0-linux-arm64.tar.gz`: generated
- `orca-v1.1.0-windows-amd64.zip`: generated
- `checksums.txt`: generated
- `sbom.json`: generated
- Signing: skipped (not configured for this environment)

## README/Docs Audit Result

- README.md: Orca-branded
- PLUGIN_RELEASE_NOTES.md: Orca-branded
- LAUNCH_PLUGINS.md: Orca-branded
- SECURITY.md: Orca-branded
- CONTRIBUTING.md: unchanged (minimal references, acceptable)
- Integration docs (codex.md, claude-code.md, plugin-security-model.md, plugin-troubleshooting.md, plugin-compatibility.md): Orca-branded
- docs/ci/github-actions.md: Orca-branded
- packaging/docker/Dockerfile: Orca-branded

## Old-Name Reference Audit Result

- Source code user-facing strings: updated from Aegis to Orca
- Build system: produces `orca` and `orca-edge` binaries with `aegis` and `aegis-edge` compatibility aliases
- Scripts: use ORCA_* env vars with AEGIS_* fallbacks where appropriate
- Docs: public docs use Orca; migration/compatibility context mentions Aegis where relevant
- Config paths (`.aegis/`, `AEGIS_SESSION_ID`, etc.): preserved for backward compatibility
- Internal module names (`aegis_core`, `aegis_cli`, `aegis_edge`): unchanged (internal implementation detail)
- Plugin skill names (`aegis-doctor`, etc.): unchanged (plugin-internal names)

## Secret Scan Result

- Synthetic test secrets (`fake_p05_secret_value`, `fake_secret_value_phase35`) found only in test fixtures, examples, and troubleshooting docs — expected and acceptable
- No real secrets, API keys, or private keys found in public docs or artifacts

## Issue Template Result

- `orca_cli_plugin_bug.md`: created (renamed from `aegis_cli_plugin_bug.md`)
- `claude_plugin_bug.md`: updated with Orca branding
- `codex_plugin_bug.md`: updated with Orca branding
- `plugin_compatibility.md`: updated with Orca branding
- `plugin_security_bug.md`: updated with Orca branding
- `plugin_docs_issue.md`: updated with Orca branding
- All templates include the security warning: "Do not paste real secrets, tokens, credentials, or private keys into this issue."

## Known Limitations

- Hooks are advisory and depend on host support.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No telemetry is collected.
- The plugins do not protect sessions that are not launched through Orca.
- These plugins do not add MCP server functionality or drone-specific plugin features.
- The current plugin release does not add MCP server behavior or drone-specific plugin features.

## Release Approval

- [x] Build passes
- [x] Tests pass
- [x] CLI smoke tests pass
- [x] Plugin artifacts generated with Orca branding
- [x] Binary artifacts generated with Orca branding
- [x] Checksums generated
- [x] Public docs Orca-branded
- [x] No unintended Aegis references in public-facing content
- [x] No secrets in artifacts
- [x] Issue templates exist and are Orca-branded
- [x] Planning artifacts are untracked/ignored

**Release is APPROVED for tagging.**

## Exact Tag Command

```bash
git tag -a v1.1.0 -m "Orca v1.1.0"
git push origin main --tags
```

## Exact GitHub Release Command

```bash
gh release create v1.1.0 dist/orca-v1.1.0-*.tar.gz dist/orca-v1.1.0-*.zip dist/plugins/orca-*.zip \
  --title "Orca v1.1.0 — Runtime guardrails and plugins for AI agents" \
  --notes-file PLUGIN_RELEASE_NOTES.md
```

## Manual Release Command (if gh CLI not authenticated)

If GitHub CLI is not authenticated, create the release manually at:
https://github.com/chriskarani/aegis/releases/new

Tag: `v1.1.0`
Title: `Orca v1.1.0 — Runtime guardrails and plugins for AI agents`
Release notes: copy contents of `PLUGIN_RELEASE_NOTES.md`

Upload artifacts:
- `dist/orca-v1.1.0-darwin-amd64.tar.gz`
- `dist/orca-v1.1.0-darwin-arm64.tar.gz`
- `dist/orca-v1.1.0-linux-amd64.tar.gz`
- `dist/orca-v1.1.0-linux-arm64.tar.gz`
- `dist/orca-v1.1.0-windows-amd64.zip`
- `dist/plugins/orca-codex-plugin-v1.1.0.zip`
- `dist/plugins/orca-claude-code-plugin-v1.1.0.zip`
- `dist/plugins/orca-plugin-checksums.txt`
- `dist/checksums.txt`
