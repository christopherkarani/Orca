# Plugin Security Model

> Scope: P01–P06 — Trust boundaries, sandbox expectations, and permission model for Aegis plugins
> Version: 1.1.0

## Core Statement

The strongest local protection remains:

```bash
aegis run -- <agent-command>
```

Aegis plugins are integration layers. They are not replacements for the Aegis runtime.

The plugin system adds:
- host-native skills
- slash commands
- lifecycle hooks
- Aegis CLI plugin commands
- policy explanations
- red-team shortcuts
- replay shortcuts

## Principles

1. **Aegis CLI is the source of truth.** Plugins call Aegis; they do not reimplement policy logic.
2. **Strongest protection is `aegis run`.** Plugin hooks are additive, not a replacement for supervised execution.
3. **Default deny.** If a plugin cannot verify safety, it must fail closed.
4. **No silent mutation.** Host configs, policies, and credentials are never changed without explicit user approval.
5. **No telemetry by default.** The plugin surface does not phone home.

## Trust Boundaries

```
┌─────────────────────────────────────────┐
│  Host IDE (Codex, Claude Code, etc.)    │  ← Untrusted by default
│  Runs arbitrary agent code                │
├─────────────────────────────────────────┤
│  Aegis Plugin (integration package)     │  ← Semi-trusted; read-only
│  Calls Aegis CLI for decisions            │
├─────────────────────────────────────────┤
│  Aegis CLI (`aegis plugin *`)           │  ← Trusted local surface
│  Owns policy, audit, replay               │
├─────────────────────────────────────────┤
│  Aegis Core (policy engine, audit)      │  ← Trusted
│  Local-only, no network dependency        │
└─────────────────────────────────────────┘
```

| Component | Trust Level | Notes |
|-----------|-------------|-------|
| Aegis core CLI | trusted | source of truth |
| Aegis plugin commands | trusted if built from Aegis | stable integration layer |
| Host plugin manifest | trusted if intentionally installed | should be reviewed |
| Hook input | untrusted | comes from agent/tool context |
| Prompt content | untrusted | may contain secrets or injection |
| Tool call | untrusted | may be model-generated |
| Host hook system | partial trust | only enforces what host supports |
| Separate repo workstreams | out of scope | must not be exposed by plugins |

## Permission Levels

| Level | What It Can Do | Example |
|-------|----------------|---------|
| **Read-only** | Query status, read policy, check manifests | `aegis plugin doctor`, `aegis plugin manifest` |
| **Preview** | Simulate changes without writing | `aegis plugin install --dry-run` |
| **Mutate** | Modify host config or policy | Requires `--yes` + explicit user confirmation |
| **Actuate** | Trigger real-world effects | **Not exposed by default** |

## Plugin Default Behavior

- `aegis plugin install` defaults to `--dry-run`.
- `aegis plugin doctor` does not print secrets or raw env values.
- Drone-related operations are default-deny.

## Credential Handling

- Plugins must not print credentials, API keys, or connection strings.
- Plugins must not store credentials in plugin-specific config files.
- Plugins must not forward credentials to remote services.

## Host Config Mutations

- Aegis plugin commands must not silently overwrite Codex, Claude Code, or other host configs.
- Any config change must be previewed with `--dry-run` first.
- Any actual change requires `--yes`.

## Sandboxing Expectations

The plugin surface does not claim to sandbox the host IDE. It provides:
- Policy queries
- Audit log summaries
- Capability reporting
- Safe installation previews

Actual sandboxing is provided by:
- `aegis run -- <command>` for child process supervision
- Host IDE's own extension sandbox (if any)
- OS-level protections

## Security Invariants

1. Plugins call Aegis; they do not reimplement Aegis.
2. Raw secrets are never persisted.
3. Hook input is bounded.
4. Hook stdout is host-valid.
5. Human logs go to stderr.
6. CI mode never prompts.
7. Deny is not silently downgraded.
8. Separate safety-sensitive workstreams are not exposed.
9. Plugin demos do not require real LLMs, real secrets, or external network.
10. Docs do not overclaim.

## What Plugins Do Not Do

- **No MCP server behavior included.** This plugin plan does not add MCP server mode.
- **No drone-specific plugin features included.** Drone work is a separate workstream.
- **No telemetry by default.** The plugin surface does not phone home.
- **No SaaS requirement.** No hosted dashboard, account, or monetization layer is required.
- **No protection for agents not launched through Aegis** unless the host hook catches the action.
- **No protection against root/admin/kernel compromise.**
- **No protection against a user approving unsafe actions.**

## Rejection Criteria

A plugin request is rejected if it would:
- Expose live drone actuation tools by default
- Auto-approve high-risk operations
- Weaken existing safety tests or policies
- Exfiltrate audit logs without redaction
- Mutate policy without explicit approval

## See Also

- `docs/integrations/aegis-cli-plugin.md`
- `docs/integrations/plugin-troubleshooting.md`
- `docs/integrations/separate-workstream-guardrails.md`
- `PLUGIN_SECURITY_MODEL.md`
