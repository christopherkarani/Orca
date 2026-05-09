# Aegis Codex Plugin

Aegis safety hooks and skills for Codex.

## What this plugin does

This plugin adds Aegis-native skills and lifecycle hooks to Codex. It lets Codex call the Aegis CLI for policy checks, red-team fixtures, session replay, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Aegis CLI remains the source of truth for all policy decisions.

## Prerequisites

- Aegis CLI built and available in PATH (or use `./zig-out/bin/aegis` from the repo)
- Zig 0.15.2 to build Aegis from source
- Codex host binary installed

## Install from local path

1. Build Aegis:
   ```bash
   zig build
   ```

2. Install the plugin locally in Codex (method depends on Codex version; consult Codex docs for the latest plugin loading mechanism).

3. Verify the plugin is recognized:
   ```bash
   aegis plugin doctor codex
   ```

## Install through repo marketplace

If your Codex version supports repo-local marketplace files, see `integrations/codex-plugin/examples/marketplace.json` for a documented example. The exact marketplace schema depends on the Codex version you are using.

## Verify install

Run the Aegis plugin doctor:

```bash
aegis plugin doctor codex
```

Expected output sections:
- Aegis version
- Policy status (present/valid)
- Plugin directories (codex: found)
- Host binaries (codex: detected or not detected)

## Available skills

| Skill | Purpose |
|-------|---------|
| `aegis-doctor` | Check Aegis installation, policy, and plugin readiness |
| `aegis-init` | Create or repair an Aegis policy for the current repo |
| `aegis-protect` | Explain how to run Codex under Aegis protection |
| `aegis-redteam` | Run deterministic red-team fixtures |
| `aegis-replay` | Show and explain the latest Aegis session replay |

## Hooks included

The plugin registers lifecycle hooks that call `aegis hook codex <event>`:

| Event | When it fires |
|-------|---------------|
| `SessionStart` | At the start of a Codex session |
| `UserPromptSubmit` | When a user submits a prompt |
| `PreToolUse` | Before Codex invokes a tool |
| `PermissionRequest` | When Codex requests user permission |
| `PostToolUse` | After Codex finishes using a tool |
| `Stop` | When the session stops |

## How hooks call Aegis

Each hook sends a JSON payload to `aegis hook codex <event>` via stdin and reads a JSON decision from stdout. The hook stdout remains valid for Codex parsing. Human-readable logs go to stderr.

Example:

```bash
echo '{"version":1,"host":"codex","event":"PreToolUse","payload":{"tool":"shell","command":"git status"}}' \
  | aegis hook codex PreToolUse
```

## Run redteam

```bash
aegis redteam --ci
```

## Replay sessions

```bash
aegis replay --session last --verify
```

## Uninstall

Remove the plugin from Codex using your Codex plugin management commands. This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory; they do not enforce policy independently of the host.
- The strongest protection remains `aegis run -- <codex-command>`.
- Plugin installation preview only; actual host plugin loading depends on Codex version.
- No telemetry is collected.

## Security model

- This plugin calls the Aegis CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than Codex hooks support.

## No MCP server behavior

This plugin does not add MCP server behavior or drone-specific plugin features.

## Strongest protection warning

> The Aegis Codex plugin adds native skills and lifecycle hooks for Codex. For the strongest local protection, run the Codex process itself through Aegis with `aegis run -- <codex-command>`.
