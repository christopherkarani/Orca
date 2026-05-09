# Plugin Launch Index

> Version: 1.1.0
> Status: P01 Complete

## Index

| Document | Purpose | Status |
|----------|---------|--------|
| `P01_AEGIS_CLI_PLUGIN_SURFACE.md` | P01 implementation summary | Complete |
| `AEGIS_CLI_PLUGIN_CONTRACT.md` | CLI-to-plugin contract | Complete |
| `PLUGIN_SECURITY_MODEL.md` | Trust boundaries and permissions | Complete |
| `DRONE_WORKSTREAM_GUARDRAILS.md` | Drone safety guardrails | Complete |
| `docs/integrations/aegis-cli-plugin.md` | User-facing plugin docs | Complete |
| `docs/integrations/plugin-security-model.md` | Security model docs | Complete |
| `docs/integrations/drone-safety.md` | Drone safety docs | Complete |
| `docs/integrations/current-baseline.md` | P00 baseline | Complete |
| `docs/integrations/drone-safepoint.md` | P00 drone safepoint | Complete |

## Phases

### P01 — Aegis CLI Plugin Surface ✅

- `aegis plugin` namespace
- `aegis plugin doctor` with JSON support
- `aegis plugin manifest` with JSON support
- `aegis plugin install` with dry-run default
- `aegis plugin mcp-server` stub
- Drone safety reporting
- Schemas and docs

### P02 — Plugin Packages (Future)

- Codex plugin package
- Claude Code plugin package
- Host-specific manifest validation
- Actual MCP server mode

### P03 — Hooks and Decisions (Future)

- `aegis hook` command
- `aegis decide` command
- Plugin lifecycle management

## Quick Start

```sh
zig build
./zig-out/bin/aegis plugin doctor
./zig-out/bin/aegis plugin doctor --json
./zig-out/bin/aegis plugin manifest codex
./zig-out/bin/aegis plugin install codex --dry-run
```

## Safety Checklist

- [x] No secrets printed in plugin doctor
- [x] No raw env values exposed
- [x] Default dry-run for install
- [x] No silent host config mutation
- [x] No telemetry added
- [x] Drone safety reporting present
- [x] MCP server stub is honest about limitations
- [x] Existing tests pass
- [x] Existing drone tests pass
