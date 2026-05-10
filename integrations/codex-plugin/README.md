# Orca Codex Plugin

Orca safety hooks and skills for Codex.

## What this plugin does

This plugin adds Orca-native skills and lifecycle hooks to Codex. It lets Codex call the Orca CLI for policy checks, red-team fixtures, session replay, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Orca CLI remains the source of truth for all policy decisions.

## Prerequisites

- Orca CLI built and available in PATH (or use `./zig-out/bin/orca` from the repo)
- Zig 0.15.2 to build Orca from source
- Codex host binary installed

## Install from local path

1. Build Orca:
   ```bash
   zig build
   ```

2. Install the plugin locally in Codex (method depends on Codex version; consult Codex docs for the latest plugin loading mechanism).

3. Verify the plugin is recognized:
   ```bash
   orca plugin doctor codex
   ```

## Install through repo marketplace

If your Codex version supports repo-local marketplace files, see `integrations/codex-plugin/examples/marketplace.json` for a documented example. The exact marketplace schema depends on the Codex version you are using.

## Verify install

Run the Orca plugin doctor:

```bash
orca plugin doctor codex
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (codex: found)
- Host binaries (codex: detected or not detected)

## Available skills

| Skill | Purpose |
|-------|---------|
| `orca-doctor` | Check Orca installation, policy, and plugin readiness |
| `orca-init` | Create or repair an Orca policy for the current repo |
| `orca-protect` | Explain how to run Codex under Orca protection |
| `orca-redteam` | Run deterministic red-team fixtures |
| `orca-replay` | Show and explain the latest Orca session replay |

## Hooks included

The plugin registers lifecycle hooks that call `orca hook codex <event>`:

| Event | When it fires |
|-------|---------------|
| `SessionStart` | At the start of a Codex session |
| `UserPromptSubmit` | When a user submits a prompt |
| `PreToolUse` | Before Codex invokes a tool |
| `PermissionRequest` | When Codex requests user permission |
| `PostToolUse` | After Codex finishes using a tool |
| `Stop` | When the session stops |

## How hooks call Orca

Each hook sends a JSON payload to `orca hook codex <event>` via stdin and reads a JSON decision from stdout. The hook stdout remains valid for Codex parsing. Human-readable logs go to stderr.

Example:

```bash
echo '{"version":1,"host":"codex","event":"PreToolUse","payload":{"tool":"shell","command":"git status"}}' \
  | orca hook codex PreToolUse
```

## Run redteam

```bash
orca redteam --ci
```

## Replay sessions

```bash
orca replay --session last --verify
```

## Uninstall

Remove the plugin from Codex using your Codex plugin management commands. This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory; they do not enforce policy independently of the host.
- The strongest protection remains `orca run -- <codex-command>`.
- Plugin installation preview only; actual host plugin loading depends on Codex version.
- No telemetry is collected.

## Security model

- This plugin calls the Orca CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than Codex hooks support.

## No MCP server behavior

This plugin does not add MCP server behavior or drone-specific plugin features.

## Strongest protection warning

> The Orca Codex plugin adds native skills and lifecycle hooks for Codex. For the strongest local protection, run the Codex process itself through Orca with `orca run -- <codex-command>`.
