# P01: Aegis CLI Plugin Surface

> Status: Implemented
> Phase: P01
> Version: 1.1.0

## Goal

Make the Aegis CLI itself plugin-capable by adding the `aegis plugin` command namespace and safe plugin-facing surfaces that later Codex and Claude Code plugins can call.

## What Was Implemented

### 1. `aegis plugin` Command Namespace

New file: `src/cli/plugin.zig`

Subcommands:
- `aegis plugin doctor`
- `aegis plugin doctor codex`
- `aegis plugin doctor claude`
- `aegis plugin manifest codex`
- `aegis plugin manifest claude`
- `aegis plugin manifest all`
- `aegis plugin install codex --dry-run`
- `aegis plugin install claude --dry-run`
- `aegis plugin install all --dry-run`
- `aegis plugin mcp-server`

### 2. `aegis plugin doctor`

Reports:
- Aegis version
- Aegis binary path
- Current working directory
- Detected workspace root
- Policy found/missing and validity
- Audit/replay availability
- MCP support status
- Plugin directories found/missing
- Codex host binary found/missing
- Claude Code host binary found/missing
- Drone workstream detected yes/no
- Drone safety mode active yes/no
- Platform capability summary
- Warnings about unsupported or partial features

Supports `--json` for machine-readable output.

Security: Does not print raw environment variables, secrets, drone credentials, or telemetry secrets.

### 3. `aegis plugin manifest`

Reports expected manifest paths:
- `integrations/codex-plugin/.codex-plugin/plugin.json`
- `integrations/claude-code-plugin/.claude-plugin/plugin.json`

If missing, reports `missing` clearly — not as an error.
Supports `--json`.

### 4. `aegis plugin install`

Defaults to safe dry-run behavior.
Requires `--yes` for actual installation.
Supports `--path` for custom plugin paths.
Does not silently overwrite user config.
Does not store credentials.
Does not add telemetry.

### 5. `aegis plugin mcp-server`

Documented stub. Reports the feature as planned/limited.
Does not start a real server.
Lists planned safe tools and blocked dangerous tools.

### 6. Drone-Aware Safety Reporting

When drone workstream is detected:
```
Drone workstream:
  detected: yes
  safety mode: plugin default-deny for live-control patterns
  simulation demos: allowed
  live control: requires explicit policy and human approval
```

### 7. Schemas

Created:
- `integrations/common/schemas/aegis-plugin-request-v1.json`
- `integrations/common/schemas/aegis-plugin-response-v1.json`

### 8. Documentation

Created/updated:
- `docs/integrations/aegis-cli-plugin.md`
- `docs/integrations/plugin-security-model.md`
- `docs/integrations/drone-safety.md`

## Files Changed

- `src/cli/plugin.zig` — new file with full plugin command implementation
- `src/cli/mod.zig` — added plugin import and dispatch
- `src/cli/help.zig` — added plugin command help text
- `integrations/common/schemas/aegis-plugin-request-v1.json` — new
- `integrations/common/schemas/aegis-plugin-response-v1.json` — new
- `docs/integrations/aegis-cli-plugin.md` — new
- `docs/integrations/plugin-security-model.md` — new
- `docs/integrations/drone-safety.md` — new
- `AEGIS_CLI_PLUGIN_CONTRACT.md` — new
- `DRONE_WORKSTREAM_GUARDRAILS.md` — new
- `PLUGIN_SECURITY_MODEL.md` — new
- `00_PLUGIN_LAUNCH_INDEX.md` — new

## Acceptance Criteria

| Criterion | Status |
|-----------|--------|
| `aegis plugin` namespace exists | ✅ |
| `aegis plugin doctor` works | ✅ |
| `aegis plugin doctor --json` works | ✅ |
| `aegis plugin manifest codex` works | ✅ |
| `aegis plugin manifest claude` works | ✅ |
| `aegis plugin install codex --dry-run` works | ✅ |
| `aegis plugin install claude --dry-run` works | ✅ |
| Safe MCP plugin server stub exists | ✅ |
| Drone safety reporting exists | ✅ |
| No secrets leak | ✅ |
| Existing Aegis tests pass | ✅ |
| Existing drone tests pass | ✅ |
| No host plugin implementation started | ✅ |

## Known Limitations

- `aegis plugin mcp-server` is a stub; no actual MCP server starts.
- `aegis plugin install` does not perform actual host installation yet.
- Codex and Claude Code plugin packages are not yet built.
- `aegis hook` and `aegis decide` are not yet implemented.

## P02 Readiness

P02 is safe to start. The plugin surface foundation is in place, tests pass, and safety invariants are preserved.
