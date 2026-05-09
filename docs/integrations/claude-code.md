# Aegis Claude Code Plugin Integration

This document describes the Aegis Claude Code plugin, how to install it, and how to use it.

## Overview

The Aegis Claude Code plugin is a local integration package that adds Aegis skills and lifecycle hooks to Claude Code. It lives under `integrations/claude-code-plugin/` in the Aegis repository.

The plugin is a thin layer. All policy decisions are made by the Aegis CLI. The plugin does not duplicate policy logic.

## Prerequisites

- Zig 0.15.2 (to build Aegis from source)
- Aegis CLI built and available in PATH
- Claude Code host binary installed

## Install instructions

### Build Aegis

```bash
zig build
```

### Install from release artifact

1. Download the latest plugin zip from the release page:
   ```text
   aegis-claude-code-plugin-vX.Y.Z.zip
   ```

2. Verify the checksum:
   ```bash
   sha256sum -c aegis-plugin-checksums.txt
   ```

3. Extract the plugin to your preferred location:
   ```bash
   unzip aegis-claude-code-plugin-vX.Y.Z.zip -d ~/aegis-plugins/claude
   ```

4. Point Claude Code to the extracted plugin directory.

### Install from local path (repo)

1. Build Aegis:
   ```bash
   zig build
   ```

2. Point Claude Code to the plugin directory:
   ```text
   integrations/claude-code-plugin/
   ```

3. Verify the plugin is recognized:
   ```bash
   ./zig-out/bin/aegis plugin doctor claude
   ```

### Local marketplace install

This repository includes a local Claude Code marketplace catalog for installing the Aegis plugin. It is not an official marketplace approval unless explicitly stated in release notes.

If your Claude Code version supports repo-local marketplace files, see:

```text
integrations/claude-marketplace/.claude-plugin/marketplace.json
```

1. Point Claude Code to the marketplace file:
   ```text
   integrations/claude-marketplace/.claude-plugin/marketplace.json
   ```

2. The catalog references the plugin source at `../claude-code-plugin` (relative to this directory).

3. Install the plugin through your Claude Code plugin management UI.

### Manual fallback install

If your Claude Code version does not support automatic plugin loading:

1. Copy the skills from `integrations/claude-code-plugin/skills/` into your Claude Code skills directory.
2. Copy the hooks from `integrations/claude-code-plugin/hooks/hooks.json` into your Claude Code hooks configuration.
3. Ensure `aegis` is in PATH or use the full path to the binary.

## Verify install

### Plugin doctor

```bash
./zig-out/bin/aegis plugin doctor claude
```

Expected output sections:
- Aegis version
- Policy status (present/valid)
- Plugin directories (claude: found)
- Host binaries (claude: detected or not detected)

### Plugin manifest

```bash
./zig-out/bin/aegis plugin manifest claude
```

This reports the expected manifest path and existence status.

### Hook smoke test

```bash
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook claude PreToolUse
```

Expected: `allow` decision in valid JSON.

### Run redteam

```bash
./zig-out/bin/aegis redteam --ci
```

### Replay last session

```bash
./zig-out/bin/aegis replay --session last --verify
```

## Skill list

| Skill | File | Purpose |
|-------|------|---------|
| `doctor` | `skills/doctor/SKILL.md` | Check installation and readiness |
| `init` | `skills/init/SKILL.md` | Create or repair a policy |
| `protect` | `skills/protect/SKILL.md` | Explain strongest protection |
| `redteam` | `skills/redteam/SKILL.md` | Run red-team fixtures |
| `replay` | `skills/replay/SKILL.md` | Replay latest session |

Skills are invoked as `/aegis:doctor`, `/aegis:init`, `/aegis:protect`, `/aegis:redteam`, `/aegis:replay` depending on the Claude Code plugin namespace configuration.

## Hook list

Hooks call `aegis hook claude <event>` with a JSON payload on stdin:

| Event | Description | Timeout |
|-------|-------------|---------|
| `SessionStart` | Session initialization check | 10s |
| `UserPromptSubmit` | Prompt secret/redaction check | 10s |
| `PreToolUse` | Tool use policy evaluation | 15s |
| `PermissionRequest` | Permission policy evaluation | 15s |
| `PostToolUse` | Post-tool acknowledgment | 10s |
| `SessionEnd` | Session end notification | 10s |

## Uninstall

Remove the plugin from Claude Code using your Claude Code plugin management commands. This plugin does not mutate host configuration, so uninstalling is safe.

If you installed from a release artifact, simply delete the extracted directory.

## Troubleshooting

### Plugin directory not found

Ensure you run `aegis plugin doctor claude` from the repository root. The doctor looks for `integrations/claude-code-plugin/` relative to the workspace root.

### Hooks timeout

If hooks exceed their timeout, Claude Code may skip them. Check that `aegis` is in PATH and that `.aegis/policy.yaml` loads quickly.

### Policy not found

Run `aegis init --preset generic-agent` to create a default policy, then validate with `aegis policy check .aegis/policy.yaml`.

### Aegis binary not found

Build Aegis with `zig build` or ensure `./zig-out/bin/aegis` is in your PATH.

### Fake secret redaction questions

The plugin uses synthetic test secrets (e.g., `fake_p05_secret_value`) in fixtures only. If you see redaction warnings about these values in test output, that is expected behavior.

### Marketplace path issues

The marketplace catalog uses a relative path (`../claude-code-plugin`). If your Claude Code version requires absolute paths, adjust the `source` field in `integrations/claude-marketplace/.claude-plugin/marketplace.json`.

## Limitations

- Hooks are advisory; enforcement depends on Claude Code host support.
- The strongest protection is `aegis run -- <claude-code-command>`.
- Plugin installation is a preview/dry-run by default.
- No telemetry is collected.
- Official marketplace availability is not yet implemented.

## Security model

- The Aegis CLI is the source of truth.
- The plugin does not reimplement policy logic.
- No secrets are stored in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.

## Separate workstream note

A separate drone workstream exists in this repository under `packages/edge/`. The Aegis Claude Code plugin does not expose or modify drone functionality.

## No MCP support

This plugin does not add MCP server behavior.

## No drone plugin support

This plugin does not add drone-specific plugin features.
