# Orca OpenCode Plugin

OpenCode plugin wrapper for Orca runtime guardrails.

## What this plugin does

This plugin adds Orca-native lifecycle hooks to OpenCode. It lets OpenCode call the Orca CLI for policy checks, audit logging, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Orca CLI remains the source of truth for all policy decisions.

## Prerequisites

- Orca CLI built and available in PATH (run `orca doctor` to verify)
- OpenCode host installed

Orca must be installed separately. The plugin does not bundle the Orca CLI.

## Install from npm

Add to your `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["orca-opencode-plugin"]
}
```

Then install dependencies:

```bash
npm install orca-opencode-plugin
```

The strongest local protection remains running OpenCode through `orca run -- opencode`; the OpenCode plugin provides native hooks and guardrails inside OpenCode.

## Install from local path

If you prefer to use the plugin directly from the Orca repository:

### Project-local install

Copy or symlink this directory into your project:

```bash
# From the Orca repo root
mkdir -p .opencode/plugins
cp integrations/opencode-plugin/orca.ts .opencode/plugins/orca.ts
```

See `examples/project-plugin-path.md` for details.

### Global install

Copy or symlink to the OpenCode global plugins directory:

```bash
mkdir -p ~/.config/opencode/plugins
cp integrations/opencode-plugin/orca.ts ~/.config/opencode/plugins/orca.ts
```

See `examples/global-plugin-path.md` for details.

### Verify the plugin is recognized

```bash
orca plugin doctor opencode
```

## Verify install

Run the Orca plugin doctor:

```bash
orca plugin doctor opencode
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (opencode: found)
- Host binaries (opencode: detected or not detected)

## Hooks included

The plugin registers lifecycle hooks that call `orca hook opencode <event>`:

| Event | When it fires | Behavior |
|-------|---------------|----------|
| `session.created` | At the start of an OpenCode session | Informational (readiness log) |
| `tool.execute.before` | Before OpenCode invokes a tool | **Blocking** — Orca can prevent the tool call |
| `tool.execute.after` | After OpenCode finishes using a tool | Informational (audit only) |
| `permission.asked` | When OpenCode requests user permission | **Blocking** — Orca can deny the permission |
| `file.edited` | When a file is edited by OpenCode | Informational (audit only) |
| `command.executed` | When a shell command is executed | Informational (audit only) |
| `session.updated` | When the session state changes | Informational (audit only) |
| `session.idle` | When the session becomes idle | Informational (audit only) |
| `session.error` | When a session error occurs | Informational (audit only) |
| `shell.env` | When the shell environment is read | Informational (secrets redacted) |

## How hooks call Orca

Each hook sends a JSON payload to `orca hook opencode <event>` via stdin and reads a JSON decision from stdout. The plugin preserves OpenCode's expected return values. Human-readable logs go to stderr.

Example payload for `tool.execute.before`:

```json
{
  "version": 1,
  "host": "opencode",
  "event": "PreToolUse",
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

Remove the plugin from your OpenCode configuration:

```bash
# npm package
npm uninstall orca-opencode-plugin

# Project-local file
rm .opencode/plugins/orca.ts

# Global file
rm ~/.config/opencode/plugins/orca.ts
```

This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory for informational events; blocking hooks depend on OpenCode honoring thrown errors.
- The strongest protection remains `orca run -- opencode`.
- Plugin installation depends on OpenCode version and plugin loading mechanism.
- No telemetry is collected.
- Official npm publication is in progress; the package structure is ready for publication.

## Security model

- This plugin calls the Orca CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Secrets are redacted from payloads before sending to Orca (keys matching `password`, `token`, `secret`, `api_key`, etc. are replaced with `[REDACTED]`).
- Hook return values remain valid for OpenCode parsing.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than OpenCode hooks support.

## No MCP server behavior

The OpenCode plugin does not add MCP server behavior or drone-specific plugin features.

## Strongest protection warning

> The Orca OpenCode plugin adds lifecycle hooks for OpenCode. For the strongest local protection, run the OpenCode process itself through Orca with `orca run -- opencode`.
