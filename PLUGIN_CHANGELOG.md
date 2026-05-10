# Aegis Plugin Changelog

## 1.1.0 — Plugin Distribution and Marketplace

### Added

- **Codex plugin** (`integrations/codex-plugin/`)
  - Plugin manifest (`.codex-plugin/plugin.json`)
  - Skills: `aegis-doctor`, `aegis-init`, `aegis-protect`, `aegis-redteam`, `aegis-replay`
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

- **Claude marketplace catalog** (`integrations/claude-marketplace/`)
  - Local marketplace example (`marketplace.json`)
  - README with usage instructions

- **Plugin packaging scripts**
  - `scripts/package-plugins.sh` — creates plugin zips and checksums
  - `scripts/package-plugins.ps1` — Windows PowerShell equivalent
  - Produces:
    - `dist/plugins/aegis-codex-plugin-vX.Y.Z.zip`
    - `dist/plugins/aegis-claude-code-plugin-vX.Y.Z.zip`
    - `dist/plugins/aegis-opencode-plugin-vX.Y.Z.zip`
    - `dist/plugins/aegis-claude-marketplace-vX.Y.Z.zip`
    - `dist/plugins/aegis-plugin-checksums.txt`

- **Plugin documentation**
  - `docs/integrations/codex.md` — Codex plugin install and usage
  - `docs/integrations/claude-code.md` — Claude Code plugin install and usage
  - `docs/integrations/opencode.md` — OpenCode plugin install and usage
  - `docs/integrations/aegis-cli-plugin.md` — Aegis CLI plugin surface reference
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
- The strongest local protection remains `aegis run -- <agent-command>`.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No MCP server behavior is included.
- No drone-specific plugin features are included.

### Compatibility

- Aegis core: 1.1.0
- Codex plugin: 1.1.0
- Claude Code plugin: 1.1.0
- OpenCode plugin: 1.1.0
- Requires Aegis CLI >= 1.0.0

---

## How to Verify This Release

```bash
# Build Aegis
zig build

# Run tests
zig build test

# Verify plugin doctors
./zig-out/bin/aegis plugin doctor codex
./zig-out/bin/aegis plugin doctor claude
./zig-out/bin/aegis plugin doctor opencode

# Verify manifests
./zig-out/bin/aegis plugin manifest codex
./zig-out/bin/aegis plugin manifest claude
./zig-out/bin/aegis plugin manifest opencode

# Verify install dry-run
./zig-out/bin/aegis plugin install codex --dry-run
./zig-out/bin/aegis plugin install claude --dry-run
./zig-out/bin/aegis plugin install opencode --dry-run

# Test hooks
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook codex PreToolUse
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook claude PreToolUse
cat tests/plugin-fixtures/opencode/tool_execute_before_safe.json \
  | ./zig-out/bin/aegis hook opencode tool.execute.before

# Package plugins
./scripts/package-plugins.sh

# Verify artifacts
ls -la dist/plugins
cat dist/plugins/aegis-plugin-checksums.txt

# Run redteam
./zig-out/bin/aegis redteam --ci
```
