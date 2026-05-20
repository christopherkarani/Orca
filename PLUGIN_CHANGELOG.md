# Orca Plugin Changelog

## 1.1.0 — Plugin Distribution and Marketplace

### Added

- **Codex plugin** (`integrations/codex-plugin/`)
  - Plugin manifest (`.codex-plugin/plugin.json`)
  - Skills: `orca-doctor`, `orca-init`, `orca-protect`, `orca-redteam`, `orca-replay`
  - Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop`
  - README with install instructions
  - Local marketplace example (`examples/marketplace.json`)

- **Claude Code plugin** (`integrations/claude-code-plugin/`)
  - Plugin manifest (`.claude-plugin/plugin.json`)
  - Skills: `doctor`, `init`, `protect`, `redteam`, `replay`
  - Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionEnd`
  - README with install instructions

- **OpenCode plugin** (`integrations/opencode-plugin/`)
  - Main file: `orca.ts`
  - Hooks: `session.created`, `tool.execute.before`, `tool.execute.after`, `permission.asked`, `permission.replied`, `file.edited`, `command.executed`, `session.updated`, `session.idle`, `session.error`, `shell.env`
  - README with install instructions

- **OpenClaw plugin** (`integrations/openclaw-plugin/`)
  - Manifest: `openclaw.plugin.json`
  - Package: `package.json` with `openclaw` field
  - Hooks: `session.start`, `tool.before`, `tool.after`, `permission.before`, `permission.after`, `session.end`
  - README with install instructions
  - npm package `orca-openclaw-plugin` prepared for distribution

- **Claude marketplace catalog** (`integrations/claude-marketplace/`)
  - Local marketplace example (`marketplace.json`)
  - README with usage instructions

- **Plugin packaging scripts**
  - `scripts/package-plugins.sh` — creates plugin zips and checksums
  - `scripts/package-plugins.ps1` — Windows PowerShell equivalent
  - `scripts/package-npm-plugins.sh` — creates npm tarballs and checksums
  - Produces:
    - `dist/plugins/orca-codex-plugin-vX.Y.Z.zip`
    - `dist/plugins/orca-claude-code-plugin-vX.Y.Z.zip`
    - `dist/plugins/orca-opencode-plugin-vX.Y.Z.zip`
    - `dist/plugins/orca-claude-marketplace-vX.Y.Z.zip`
    - `dist/plugins/orca-plugin-checksums.txt`
    - `dist/npm/orca-opencode-plugin-vX.Y.Z.tgz`
    - `dist/npm/orca-openclaw-plugin-vX.Y.Z.tgz`
    - `dist/npm/orca-npm-plugin-checksums.txt`

- **Plugin documentation**
  - `docs/integrations/codex.md` — Codex plugin install and usage
  - `docs/integrations/claude-code.md` — Claude Code plugin install and usage
  - `docs/integrations/opencode.md` — OpenCode plugin install and usage
  - `docs/integrations/orca-plugin.md` — Orca plugin surface reference
  - `docs/integrations/plugin-troubleshooting.md` — Common issues and fixes
  - `docs/integrations/plugin-security-model.md` — Trust boundaries and invariants
  - `docs/integrations/separate-workstream-guardrails.md` — Drone workstream isolation
  - `docs/integrations/plugin-compatibility.md` — Feature matrix

- **Release workflow updates**
  - Plugin packaging step added to `.github/workflows/release.yml`
  - Plugin artifacts uploaded alongside release binaries
  - Secret scan step runs before artifact upload

### Security

- No raw secrets in plugin artifacts.
- No raw secrets in documentation.
- No telemetry.
- No silent config mutation.
- Plugin install docs are reversible.
- Checksums generated for all plugin zips.
- Secret scan runs over artifacts before release.

### Known Limitations

- Hooks are advisory; they do not enforce policy independently of the host.
- The strongest local protection remains `orca run -- <agent-command>`.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No MCP server behavior is included.
- No drone-specific plugin features are included.

### Compatibility

- Orca core: 1.1.0
- Codex plugin: 1.1.0
- Claude Code plugin: 1.1.0
- OpenCode plugin: 1.1.0
- OpenClaw plugin npm package: 1.1.3 (published as `orca-openclaw-plugin`)
- OpenClaw ClawHub submission: published in P11 as `orca-openclaw-plugin@1.1.3`
- Requires Orca >= 1.0.0

---

## How to Verify This Release

```bash
# Build Orca
zig build

# Run tests
zig build test

# Verify plugin doctors
./zig-out/bin/orca plugin doctor codex
./zig-out/bin/orca plugin doctor claude
./zig-out/bin/orca plugin doctor opencode

# Verify manifests
./zig-out/bin/orca plugin manifest codex
./zig-out/bin/orca plugin manifest claude
./zig-out/bin/orca plugin manifest opencode

# Verify install dry-run
./zig-out/bin/orca plugin install codex --dry-run
./zig-out/bin/orca plugin install claude --dry-run
./zig-out/bin/orca plugin install opencode --dry-run

# Test hooks
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json \
  | ./zig-out/bin/orca hook codex PreToolUse
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/orca hook claude PreToolUse
cat tests/plugin-fixtures/opencode/tool_execute_before_safe.json \
  | ./zig-out/bin/orca hook opencode tool.execute.before

# Package plugins
./scripts/package-plugins.sh

# Verify artifacts
ls -la dist/plugins
cat dist/plugins/orca-plugin-checksums.txt

# Run redteam
./zig-out/bin/orca redteam --ci
```
