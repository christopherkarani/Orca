# Aegis Codex Plugin Integration

This document describes the Aegis Codex plugin, how to install it, and how to use it.

## Overview

The Aegis Codex plugin is a local integration package that adds Aegis skills and lifecycle hooks to Codex. It lives under `integrations/codex-plugin/` in the Aegis repository.

The plugin is a thin layer. All policy decisions are made by the Aegis CLI. The plugin does not duplicate policy logic.

## Install instructions

### Build Aegis

```bash
zig build
```

### Verify plugin status

```bash
./zig-out/bin/aegis plugin doctor codex
```

### Load the plugin in Codex

Codex plugin loading mechanisms vary by version. The plugin directory is:

```text
integrations/codex-plugin/
```

Point Codex to this directory using its local plugin loading feature.

## Local marketplace example

If your Codex version supports repo-local marketplace files, see:

```text
integrations/codex-plugin/examples/marketplace.json
```

This is a documented example only. The exact schema depends on your Codex version.

## Skill list

| Skill | File | Purpose |
|-------|------|---------|
| `aegis-doctor` | `skills/aegis-doctor/SKILL.md` | Check installation and readiness |
| `aegis-init` | `skills/aegis-init/SKILL.md` | Create or repair a policy |
| `aegis-protect` | `skills/aegis-protect/SKILL.md` | Explain strongest protection |
| `aegis-redteam` | `skills/aegis-redteam/SKILL.md` | Run red-team fixtures |
| `aegis-replay` | `skills/aegis-replay/SKILL.md` | Replay latest session |

## Hook list

Hooks call `aegis hook codex <event>` with a JSON payload on stdin:

| Event | Description | Timeout |
|-------|-------------|---------|
| `SessionStart` | Session initialization check | 10s |
| `UserPromptSubmit` | Prompt secret/redaction check | 10s |
| `PreToolUse` | Tool use policy evaluation | 15s |
| `PermissionRequest` | Permission policy evaluation | 15s |
| `PostToolUse` | Post-tool acknowledgment | 10s |
| `Stop` | Session stop notification | 10s |

## Verify commands

```bash
# Check plugin structure
./zig-out/bin/aegis plugin manifest codex

# Run plugin doctor
./zig-out/bin/aegis plugin doctor codex

# Test a hook with a fixture
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook codex PreToolUse

# Run redteam
./zig-out/bin/aegis redteam --ci

# Replay last session
./zig-out/bin/aegis replay --session last --verify
```

## Limitations

- Hooks are advisory; enforcement depends on Codex host support.
- The strongest protection is `aegis run -- <codex-command>`.
- Plugin installation is a preview/dry-run by default.
- No telemetry is collected.
- Official marketplace availability is not yet implemented.

## Troubleshooting

### Plugin directory not found

Ensure you run `aegis plugin doctor codex` from the repository root. The doctor looks for `integrations/codex-plugin/` relative to the workspace root.

### Hooks timeout

If hooks exceed their timeout, Codex may skip them. Check that `aegis` is in PATH and that `.aegis/policy.yaml` loads quickly.

### Policy not found

Run `aegis init --preset codex` to create a default policy, then validate with `aegis policy check .aegis/policy.yaml`.

## Security model

- The Aegis CLI is the source of truth.
- The plugin does not reimplement policy logic.
- No secrets are stored in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.

## Separate workstream note

A separate drone workstream exists in this repository under `packages/edge/`. The Aegis Codex plugin does not expose or modify drone functionality.
