# Aegis CLI Plugin Contract

> Version: 1.1.0
> Status: Active

## What This Document Is

This document defines the contract between the Aegis CLI and host plugins (Codex, Claude Code, and future integrations).

## Core Promise

**The Aegis CLI is the source of truth.** Plugins call Aegis instead of duplicating policy logic.

## Contract Terms

### 1. Policy Authority

Aegis owns policy loading, validation, evaluation, and explanation. Plugins must not:
- Reimplement policy parsing
- Cache policy decisions beyond a single session
- Override Aegis policy decisions silently

### 2. Audit Integrity

Aegis owns audit log writing, hash chains, and replay. Plugins must not:
- Write directly to audit session files
- Bypass audit for actions taken on behalf of the user
- Forge or modify audit hashes

### 3. Capability Reporting

Aegis reports platform capabilities honestly via `aegis doctor` and `aegis plugin doctor`. Plugins must:
- Trust Aegis capability reports over their own assumptions
- Surface capability limits to the user
- Not claim protections that Aegis does not report as active

### 4. Safe Defaults

Plugin-facing commands default to safe behavior:
- `aegis plugin install` defaults to `--dry-run`
- `aegis plugin doctor` does not print secrets
- `aegis plugin mcp-server` is a documented stub

### 5. No Silent Mutation

Aegis plugin commands must not silently mutate:
- Host IDE configuration
- User shell config
- Aegis policy files
- Environment variables

Any mutation requires `--yes` or explicit user confirmation.

### 6. No Telemetry

Aegis does not collect telemetry through the plugin surface. Plugins must not:
- Send Aegis operation data to remote services
- Embed analytics in plugin-to-Aegis calls
- Require network access to function

### 7. Version Stability

Aegis exposes its version via `aegis version --json`. Plugins can use this to:
- Detect feature availability
- Warn about version mismatches
- Gate functionality behind minimum versions

### 8. Drone Safety

When the Aegis Edge workstream is present, plugins must:
- Respect the default-deny policy for live-control patterns
- Use simulation-only demos
- Require explicit policy and human approval for live operations

## Plugin Responsibilities

A host plugin that integrates with Aegis must:

1. **Call Aegis for decisions.** Do not reimplement policy logic.
2. **Respect dry-run defaults.** Preview changes before applying.
3. **Surface limitations.** Tell the user when Aegis reports partial or unavailable capabilities.
4. **Preserve audit trails.** Ensure user actions that trigger Aegis checks are auditable.
5. **Fail closed.** If Aegis is unavailable, default to safe behavior.

## CLI Contract Surface

The following commands form the stable contract:

| Command | Stability | Purpose |
|---------|-----------|---------|
| `aegis plugin doctor` | Stable | Health check and capability report |
| `aegis plugin doctor --json` | Stable | Machine-readable health check |
| `aegis plugin manifest codex` | Stable | Manifest path/status |
| `aegis plugin manifest claude` | Stable | Manifest path/status |
| `aegis plugin install * --dry-run` | Stable | Installation preview |
| `aegis plugin mcp-server` | Unstable | Stub; full implementation deferred |

## Breaking Changes

Breaking changes to the plugin contract will be:
- Documented in release notes
- Version-gated where possible
- Announced with a migration path

## See Also

- `docs/integrations/aegis-cli-plugin.md`
- `docs/integrations/plugin-security-model.md`
