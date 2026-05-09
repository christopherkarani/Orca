# Aegis Claude Code Plugin Integration

This document describes the Aegis Claude Code plugin, how to install it, and how to use it.

## Overview

The Aegis Claude Code plugin is a local integration package that adds Aegis skills and lifecycle hooks to Claude Code. It lives under `integrations/claude-code-plugin/` in the Aegis repository.

The plugin is a thin layer. All policy decisions are made by the Aegis CLI. The plugin does not duplicate policy logic.

## Install instructions

### Build Aegis

```bash
zig build
```

### Verify plugin status

```bash
./zig-out/bin/aegis plugin doctor claude
```

### Load the plugin in Claude Code

Claude Code plugin loading mechanisms vary by version. The plugin directory is:

```text
integrations/claude-code-plugin/
```

Point Claude Code to this directory using its local plugin loading feature.

## Local marketplace instructions

If your Claude Code version supports repo-local marketplace files, see:

```text
integrations/claude-marketplace/.claude-plugin/marketplace.json
```

This is a documented example only. The exact schema depends on your Claude Code version.

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

## Verify commands

```bash
# Check plugin structure
./zig-out/bin/aegis plugin manifest claude

# Run plugin doctor
./zig-out/bin/aegis plugin doctor claude

# Test a hook with a fixture
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook claude PreToolUse

# Run redteam
./zig-out/bin/aegis redteam --ci

# Replay last session
./zig-out/bin/aegis replay --session last --verify
```

## Limitations

- Hooks are advisory; enforcement depends on Claude Code host support.
- The strongest protection is `aegis run -- <claude-code-command>`.
- Plugin installation is a preview/dry-run by default.
- No telemetry is collected.
- Official marketplace availability is not yet implemented.

## Troubleshooting

### Plugin directory not found

Ensure you run `aegis plugin doctor claude` from the repository root. The doctor looks for `integrations/claude-code-plugin/` relative to the workspace root.

### Hooks timeout

If hooks exceed their timeout, Claude Code may skip them. Check that `aegis` is in PATH and that `.aegis/policy.yaml` loads quickly.

### Policy not found

Run `aegis init --preset generic-agent` to create a default policy, then validate with `aegis policy check .aegis/policy.yaml`.

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
