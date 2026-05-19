# Orca OpenClaw Plugin

OpenClaw plugin wrapper for Orca runtime guardrails.

## What this plugin does

This plugin adds Orca-native lifecycle hooks to OpenClaw. It lets OpenClaw call the Orca CLI for policy checks, audit logging, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Orca CLI remains the source of truth for all policy decisions.

## Prerequisites

- Orca CLI built and available in PATH (run `orca doctor` to verify)
- OpenClaw host installed

Orca is not bundled into this plugin package. Fast setup:

```bash
./scripts/install-orca-plugin.sh openclaw project
```

Windows:

```powershell
.\scripts\install-orca-plugin.ps1 openclaw project
```

## Install from local path

If you have OpenClaw installed locally:

```bash
openclaw plugins install ./integrations/openclaw-plugin
```

The strongest local protection remains running OpenClaw through `orca run -- openclaw`; the OpenClaw plugin provides native guardrails where OpenClaw plugin hooks support them.

## Install from npm

After npm publication, install with:

```bash
openclaw plugins install npm:orca-openclaw-plugin
```

If OpenClaw supports bare npm package installs:

```bash
openclaw plugins install orca-openclaw-plugin
```

For local validation before publication, use `npm pack --dry-run`.


## Install from ClawHub

The plugin is published to ClawHub as `orca-openclaw-plugin`.

```bash
openclaw plugins install clawhub:orca-openclaw-plugin
```

**Note:** The `clawhub:` install protocol requires a recent OpenClaw version. If your version does not support it, use the local path or npm install methods instead.

For submission details, see `docs/integrations/openclaw-clawhub.md`.

## Verify install

Run the Orca plugin doctor:

```bash
orca plugin doctor openclaw
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (openclaw: found)
- Host binaries (openclaw: detected or not detected)

## Hooks included

The plugin registers lifecycle hooks that call `orca hook openclaw <event>`:

| Event | When it fires | Behavior |
|-------|---------------|----------|
| `session.start` | At the start of an OpenClaw session | Informational (readiness log) |
| `tool.before` | Before OpenClaw invokes a tool | **Blocking** — Orca can prevent the tool call |
| `tool.after` | After OpenClaw finishes using a tool | Informational (audit only) |
| `session.end` | When the session ends | Informational (audit only) |

OpenClaw does not currently expose dedicated permission lifecycle hooks to this plugin. Permission-like blocking is handled through `tool.before` before the tool call executes.

## How hooks call Orca

Each hook sends a JSON payload to `orca hook openclaw <event>` via stdin and reads a JSON decision from stdout. The plugin preserves OpenClaw's expected return values. Human-readable logs go to stderr.

Example payload for `tool.before`:

```json
{
  "version": 1,
  "host": "openclaw",
  "event": "tool.before",
  "payload": {
    "tool": "shell",
    "command": "git status"
  },
  "session_id": "session-uuid",
  "timestamp": "2026-01-01T00:00:00Z"
}
```

Example response:

```json
{
  "version": 1,
  "decision": "allow",
  "risk": "low",
  "category": "command",
  "reason": "policy_allow",
  "message": "Allowed by policy"
}
```

If the decision is `block`, the plugin throws an error that prevents the tool from executing.

## Run redteam

```bash
orca redteam --ci
```

## Replay sessions

```bash
orca replay --session last --verify
```

## Uninstall

Remove the plugin from your OpenClaw configuration:

```bash
openclaw plugins uninstall orca
```

This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory for informational events; blocking hooks depend on OpenClaw honoring thrown errors.
- The strongest protection remains `orca run -- openclaw`.
- Plugin installation depends on OpenClaw version and plugin loading mechanism.
- No telemetry is collected.
- npm package support has been prepared for `orca-openclaw-plugin`.
- ClawHub submission is complete. The plugin is published as `orca-openclaw-plugin@1.1.3`.

## Security model

- This plugin calls the Orca CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Secrets are redacted from payloads before sending to Orca (keys matching `password`, `token`, `secret`, `api_key`, etc. are replaced with `[REDACTED]`).
- Hook return values remain valid for OpenClaw parsing.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than OpenClaw hooks support.

## No MCP server behavior

The OpenClaw plugin does not add MCP server behavior or drone-specific plugin features.

## Strongest protection warning

> The Orca OpenClaw plugin adds lifecycle hooks for OpenClaw. For the strongest local protection, run the OpenClaw process itself through Orca with `orca run -- openclaw`.
