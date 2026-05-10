# Orca Plugin Release Notes

## Version: 1.1.0

Orca 1.1.0 introduces the first native plugin release for Codex and Claude Code. The plugins add host-native commands, hooks, and diagnostics while keeping Orca CLI as the source of truth for policy, replay, and security decisions.

## Orca CLI plugin surface

Both host integrations call into the same CLI surface:

- `orca plugin doctor` — reports Orca version, workspace state, policy status, host binary detection, plugin directories, and platform capabilities.
- `orca plugin manifest` — reports the expected plugin manifest path and whether it exists.
- `orca plugin install` — previews or performs installation from a release artifact or local path; it defaults to `--dry-run` and requires `--yes` for a real mutation.
- `orca decide` — returns stable JSON decisions for commands, files, prompts, and tool calls.
- `orca hook` — processes host lifecycle hooks with JSON payloads on stdin.

## Codex plugin

- Path: `integrations/codex-plugin/`
- Manifest: `integrations/codex-plugin/.codex-plugin/plugin.json`
- Skills: `aegis-doctor`, `aegis-init`, `aegis-protect`, `aegis-redteam`, `aegis-replay`
- Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop`
- Install guide: [docs/integrations/codex.md](docs/integrations/codex.md)

The Codex plugin is a thin host integration. It does not reimplement policy logic or add MCP behavior.

## Claude Code plugin

- Path: `integrations/claude-code-plugin/`
- Manifest: `integrations/claude-code-plugin/.claude-plugin/plugin.json`
- Skills: `doctor`, `init`, `protect`, `redteam`, `replay`
- Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionEnd`
- Install guide: [docs/integrations/claude-code.md](docs/integrations/claude-code.md)

The Claude Code plugin is also a thin host integration. It delegates policy and replay to Orca CLI and does not add drone-specific plugin features.

## OpenCode plugin

- Path: `integrations/opencode-plugin/`
- Main file: `integrations/opencode-plugin/orca.ts`
- Hooks: `session.created`, `tool.execute.before`, `tool.execute.after`, `permission.asked`, `permission.replied`, `file.edited`, `command.executed`, `session.updated`, `session.idle`, `session.error`, `shell.env`
- Install guide: [docs/integrations/opencode.md](docs/integrations/opencode.md)

The OpenCode plugin is a thin host integration. It delegates policy and replay to Orca CLI and does not add drone-specific plugin features. OpenCode uses hooks, not skills.

## OpenClaw plugin

- Path: `integrations/openclaw-plugin/`
- Manifest: `integrations/openclaw-plugin/openclaw.plugin.json`
- Package: `integrations/openclaw-plugin/package.json`
- Hooks: `session_start` → `session.start`, `before_tool_call` → `tool.before`, `after_tool_call` → `tool.after`, `session_end` → `session.end`
- Install guide: [docs/integrations/openclaw.md](docs/integrations/openclaw.md)

The OpenClaw plugin is a thin host integration. It delegates policy and replay to Orca CLI and does not add drone-specific plugin features. OpenClaw uses hooks, not skills. npm package `orca-openclaw-plugin@1.1.3` is published; ClawHub package `orca-openclaw-plugin@1.1.3` is published.

## Installation

### From a release artifact

1. Download the release zip for your host:
   - `orca-codex-plugin-vX.Y.Z.zip`
   - `orca-claude-code-plugin-vX.Y.Z.zip`
   - `orca-opencode-plugin-vX.Y.Z.zip`
   - `orca-openclaw-plugin-vX.Y.Z.zip`
2. Verify the checksum file before extracting anything:
   ```sh
   sha256sum -c orca-plugin-checksums.txt
   ```
3. Extract the plugin to a local directory of your choice.
4. Point Codex, Claude Code, OpenCode, or OpenClaw at the extracted plugin directory.

### From npm

After npm publication, install the OpenClaw plugin with:

```bash
openclaw plugins install npm:orca-openclaw-plugin
```

For local validation before publication, use `npm pack --dry-run` in `integrations/openclaw-plugin/`.

### From a repo marketplace

**Codex:**
```bash
codex plugin marketplace add YOUR_ORG/orca
```
Then install Orca from Codex's plugin UI/directory after adding the marketplace.

**Claude Code:**
```bash
claude plugin marketplace add YOUR_ORG/orca
claude plugin install orca@orca --scope user
```

These commands add the Orca repository as a plugin marketplace source. This is not the same as being listed in the official Codex or Claude marketplace.

### From a local path

1. Build Orca:
   ```sh
   zig build
   ```
2. Point your host at the repository path:
   - Codex: `integrations/codex-plugin/`
   - Claude Code: `integrations/claude-code-plugin/`
   - OpenCode: `integrations/opencode-plugin/`
   - OpenClaw: `integrations/openclaw-plugin/`
 3. Confirm the plugin is visible:
    ```sh
    ./zig-out/bin/orca plugin doctor codex
    ./zig-out/bin/orca plugin doctor claude
    ./zig-out/bin/orca plugin doctor opencode
    ./zig-out/bin/orca plugin doctor openclaw
    ```
 
 ### Checksum verification
 
 Always verify `orca-plugin-checksums.txt` before installing a release zip. The checksum file is the release gate for `dist/plugins/orca-codex-plugin-vX.Y.Z.zip`, `dist/plugins/orca-claude-code-plugin-vX.Y.Z.zip`, `dist/plugins/orca-opencode-plugin-vX.Y.Z.zip`, and `dist/plugins/orca-openclaw-plugin-vX.Y.Z.zip`.

## Verification

Run these commands from the repository root:

```sh
zig build
zig build test
./zig-out/bin/orca plugin doctor codex
./zig-out/bin/orca plugin doctor claude
./zig-out/bin/orca plugin doctor opencode
./zig-out/bin/orca plugin doctor openclaw
./zig-out/bin/orca plugin manifest codex
./zig-out/bin/orca plugin manifest claude
./zig-out/bin/orca plugin manifest opencode
./zig-out/bin/orca plugin manifest openclaw
./zig-out/bin/orca plugin install codex --dry-run
./zig-out/bin/orca plugin install claude --dry-run
./zig-out/bin/orca plugin install opencode --dry-run
./zig-out/bin/orca plugin install openclaw --dry-run
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json | ./zig-out/bin/orca hook codex PreToolUse
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json | ./zig-out/bin/orca hook claude PreToolUse
cat tests/plugin-fixtures/opencode/tool_execute_before_safe.json | ./zig-out/bin/orca hook opencode tool.execute.before
cat tests/plugin-fixtures/openclaw/tool_command_safe.json | ./zig-out/bin/orca hook openclaw tool.before
./zig-out/bin/orca redteam --ci
./zig-out/bin/orca replay --session last --verify
./scripts/package-plugins.sh
./scripts/package-npm-plugins.sh
```

## Demo

See [examples/plugin-demo/](examples/plugin-demo/) for the local demo flow.

## Security model

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

Orca CLI remains the source of truth for policy decisions, replay, and audit behavior. Plugins are additive host integrations, not a replacement for supervised execution.

## Known limitations

- Hooks are advisory and depend on host support.
- Official marketplace availability is not yet implemented.
- Plugin installation is preview/dry-run by default.
- No telemetry is collected.
- The plugins do not protect sessions that are not launched through Orca.
- These plugins do not add MCP server functionality or drone-specific plugin features.

## Checksums

- Release checksum file: `dist/plugins/orca-plugin-checksums.txt`
- Verification command: `sha256sum -c orca-plugin-checksums.txt`
- Release zips:
  - `dist/plugins/orca-codex-plugin-vX.Y.Z.zip`
  - `dist/plugins/orca-claude-code-plugin-vX.Y.Z.zip`
  - `dist/plugins/orca-opencode-plugin-vX.Y.Z.zip`

## Vulnerability reporting

Report security issues privately through [SECURITY.md](SECURITY.md).

## Contribution guidance

Read [CONTRIBUTING.md](CONTRIBUTING.md), add deterministic tests or fixtures for security-sensitive changes, and verify with:

```sh
zig build
zig build test
./zig-out/bin/orca redteam --ci
```

## Troubleshooting links

- [docs/integrations/plugin-troubleshooting.md](docs/integrations/plugin-troubleshooting.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/integrations/codex.md](docs/integrations/codex.md)
- [docs/integrations/claude-code.md](docs/integrations/claude-code.md)
- [docs/integrations/opencode.md](docs/integrations/opencode.md)
- [PLUGIN_SECURITY_MODEL.md](PLUGIN_SECURITY_MODEL.md)
