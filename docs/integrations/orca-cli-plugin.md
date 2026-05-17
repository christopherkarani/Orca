# Orca CLI Plugin Surface

> Scope: P01 — Orca CLI plugin namespace and safe plugin-facing surfaces
> Version: 1.1.0

## Overview

The Orca CLI itself is now plugin-capable. This means:

- The `orca` binary exposes a `plugin` command namespace.
- Host plugins (Codex, Claude Code, and future integrations) call the Orca CLI instead of duplicating policy logic.
- The Orca CLI remains the source of truth for policy, audit, replay, and capability reporting.

## Commands

### `orca plugin doctor`

Reports Orca version, workspace state, policy presence, host binary detection, plugin directory status, and platform capabilities.

```sh
orca plugin doctor
orca plugin doctor --json
orca plugin doctor codex
orca plugin doctor claude
orca plugin doctor codex --json
orca plugin doctor claude --json
```

**Security properties:**
- Does not print raw environment variable values.
- Does not print secrets, credentials, or connection strings.
- Does not claim a host plugin is installed unless detected.
- Does not claim a protection is active unless it is actually active.

### `orca plugin manifest`

Reports the expected plugin manifest path and existence status.

```sh
orca plugin manifest codex
orca plugin manifest claude
orca plugin manifest all
orca plugin manifest codex --json
```

If a manifest does not exist yet, it reports `missing` clearly — not as an error.

Expected paths:
- Codex: `integrations/codex-plugin/.codex-plugin/plugin.json`
- Claude Code: `integrations/claude-code-plugin/.claude-plugin/plugin.json`

### `orca plugin install`

Previews or performs plugin installation. Defaults to safe dry-run behavior.

```sh
orca plugin install codex --dry-run
orca plugin install claude --dry-run
orca plugin install all --dry-run
orca plugin install codex --path <plugin-path> --dry-run
```

**Safety rules:**
- Defaults to `--dry-run` if the actual host install command is not known.
- Never silently overwrites user config.
- Requires `--yes` for non-dry-run installation.
- Does not mutate Codex or Claude config silently.
- Does not store credentials.
- Does not add telemetry.

### `orca decide`

Exposes stable JSON decisions for commands, files, prompts, and host tool calls.

```sh
orca decide command --json '{"version":1,"host":"codex","command":"git status"}'
orca decide command --json '{"version":1,"host":"claude","command":"git status"}'
orca decide file --json '{"version":1,"host":"codex","path":"/etc/passwd","operation":"write"}'
orca decide prompt --json '{"version":1,"host":"claude","prompt":"hello"}'
orca decide tool --json '{"version":1,"host":"codex","tool":"shell","command":"ls"}'
```

### `orca hook`

Processes host plugin lifecycle hooks with JSON payloads on stdin.

```sh
echo '{"version":1,"host":"codex","event":"PreToolUse","payload":{"tool":"shell","command":"git status"}}' \
  | orca hook codex PreToolUse
```

## Plugin Packaging

Plugin artifacts are packaged by `scripts/package-plugins.sh` (and `scripts/package-plugins.ps1` on Windows).

Packaged artifacts:

```text
dist/plugins/orca-codex-plugin-vX.Y.Z.zip
dist/plugins/orca-claude-code-plugin-vX.Y.Z.zip
dist/plugins/orca-plugin-checksums.txt
```

Artifact contents include:
- Plugin manifest (`plugin.json`)
- Skills directory
- Hooks configuration (`hooks.json`)
- README

Artifacts exclude:
- `.mcp.json`
- Drone files
- Build artifacts
- Temporary files
- Secrets

## Install dry-run behavior

`orca plugin install` defaults to `--dry-run`. In dry-run mode:
- The command previews what would be installed.
- No host configuration is mutated.
- The user sees the plugin path, manifest status, and host compatibility.

For actual installation, use `--yes`:
```sh
orca plugin install codex --yes
```

## Host limitations

Plugin hooks are limited by host capabilities. Orca cannot enforce what the host IDE does not expose.

- Codex hooks: advisory; enforcement depends on Codex host support.
- Claude Code hooks: advisory; enforcement depends on Claude Code host support.

## Architecture

```
Host IDE (Codex / Claude Code / Cursor / ...)
    |
    v
Orca CLI plugin surface  <--  orca plugin doctor / manifest / install
    |
    v
Orca Core (policy, audit, replay, decision engine)
```

Plugins call Orca instead of duplicating policy logic. The strongest local protection remains:

```sh
orca run -- <agent-command>
```

## No Telemetry, No SaaS

- No telemetry is collected by the plugin surface.
- No SaaS account, dashboard, or monetization layer is required.
- All operations are local to the machine.

## Drone Safety Reporting

When the Orca Edge workstream is detected, `orca plugin doctor` includes a drone safety section:

```
Drone workstream:
  detected: yes
  safety mode: plugin default-deny for live-control patterns
  simulation demos: allowed
  live control: requires explicit policy and human approval
```

Live drone operations are classified as safety-critical and require explicit policy and human approval.

## Schemas

Plugin request/response schemas live in:
- `integrations/common/schemas/orca-plugin-request-v1.json`
- `integrations/common/schemas/orca-plugin-response-v1.json`

Hook request/response schemas live in:
- `integrations/common/schemas/hook-request-v1.json`
- `integrations/common/schemas/hook-response-v1.json`

## Compatibility

Orca plugins 1.x require Orca CLI >= 1.0.0.

| Component | Version |
|-----------|---------|
| Orca core | 1.1.0 |
| Codex plugin | 1.1.0 |
| Claude Code plugin | 1.1.0 |

## See Also

- `docs/integrations/plugin-security-model.md`
- `docs/integrations/plugin-troubleshooting.md`
- `docs/integrations/plugin-compatibility.md`
- `docs/integrations/drone-safety.md`
- `ORCA_CLI_PLUGIN_CONTRACT.md`
- `PLUGIN_SECURITY_MODEL.md`
