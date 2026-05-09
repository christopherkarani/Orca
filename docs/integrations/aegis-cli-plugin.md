# Aegis CLI Plugin Surface

> Scope: P01 — Aegis CLI plugin namespace and safe plugin-facing surfaces
> Version: 1.1.0

## Overview

The Aegis CLI itself is now plugin-capable. This means:

- The `aegis` binary exposes a `plugin` command namespace.
- Host plugins (Codex, Claude Code, and future integrations) call the Aegis CLI instead of duplicating policy logic.
- The Aegis CLI remains the source of truth for policy, audit, replay, and capability reporting.

## Commands

### `aegis plugin doctor`

Reports Aegis version, workspace state, policy presence, host binary detection, plugin directory status, and platform capabilities.

```sh
aegis plugin doctor
aegis plugin doctor --json
aegis plugin doctor codex
aegis plugin doctor claude
aegis plugin doctor codex --json
aegis plugin doctor claude --json
```

**Security properties:**
- Does not print raw environment variable values.
- Does not print secrets, credentials, or connection strings.
- Does not claim a host plugin is installed unless detected.
- Does not claim a protection is active unless it is actually active.

### `aegis plugin manifest`

Reports the expected plugin manifest path and existence status.

```sh
aegis plugin manifest codex
aegis plugin manifest claude
aegis plugin manifest all
aegis plugin manifest codex --json
```

If a manifest does not exist yet, it reports `missing` clearly — not as an error.

Expected paths:
- Codex: `integrations/codex-plugin/.codex-plugin/plugin.json`
- Claude Code: `integrations/claude-code-plugin/.claude-plugin/plugin.json`

### `aegis plugin install`

Previews or performs plugin installation. Defaults to safe dry-run behavior.

```sh
aegis plugin install codex --dry-run
aegis plugin install claude --dry-run
aegis plugin install all --dry-run
aegis plugin install codex --path <plugin-path> --dry-run
```

**Safety rules:**
- Defaults to `--dry-run` if the actual host install command is not known.
- Never silently overwrites user config.
- Requires `--yes` for non-dry-run installation.
- Does not mutate Codex or Claude config silently.
- Does not store credentials.
- Does not add telemetry.

### `aegis plugin mcp-server`

Currently a documented stub. Reports the feature as planned/limited and does not start a real server.

When implemented, the MCP server will expose only safe Aegis CLI functions as MCP tools:

**Planned safe tools:**
- `aegis_doctor`
- `aegis_plugin_doctor`
- `aegis_policy_check`
- `aegis_policy_explain`
- `aegis_redteam`
- `aegis_replay_summary`
- `aegis_capabilities`
- `aegis_drone_safety_status`

**Blocked by default (not exposed):**
- Arbitrary shell execution
- Arbitrary file writes
- Raw audit log dumping without redaction
- Credential access
- Policy mutation without explicit approval
- Live drone actuation commands

## Architecture

```
Host IDE (Codex / Claude Code / Cursor / ...)
    |
    v
Aegis CLI plugin surface  <--  aegis plugin doctor / manifest / install
    |
    v
Aegis Core (policy, audit, replay, decision engine)
```

Plugins call Aegis instead of duplicating policy logic. The strongest local protection remains:

```sh
aegis run -- <agent-command>
```

Plugin hooks are limited by host capabilities. Aegis cannot enforce what the host IDE does not expose.

## Drone Safety Reporting

When the Aegis Edge workstream is detected, `aegis plugin doctor` includes a drone safety section:

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
- `integrations/common/schemas/aegis-plugin-request-v1.json`
- `integrations/common/schemas/aegis-plugin-response-v1.json`

## No Telemetry, No SaaS

- No telemetry is collected by the plugin surface.
- No SaaS account, dashboard, or monetization layer is required.
- All operations are local to the machine.

## Future Work (P02+)

- Actual Codex plugin package
- Actual Claude Code plugin package
- `aegis hook` command
- `aegis decide` command
- Full MCP server mode with stdio transport

## See Also

- `docs/integrations/plugin-security-model.md`
- `docs/integrations/drone-safety.md`
- `AEGIS_CLI_PLUGIN_CONTRACT.md`
- `PLUGIN_SECURITY_MODEL.md`
