# Aegis Claude Code Plugin

Aegis safety hooks and skills for Claude Code.

## What this plugin does

This plugin adds Aegis-native skills and lifecycle hooks to Claude Code. It lets Claude Code call the Aegis CLI for policy checks, red-team fixtures, session replay, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Aegis CLI remains the source of truth for all policy decisions.

## Prerequisites

- Aegis CLI built and available in PATH (or use `./zig-out/bin/aegis` from the repo)
- Zig 0.15.2 to build Aegis from source
- Claude Code host binary installed

## Install from local path

1. Build Aegis:
   ```bash
   zig build
   ```

2. Install the plugin locally in Claude Code (method depends on Claude Code version; consult Claude Code docs for the latest plugin loading mechanism).

3. Verify the plugin is recognized:
   ```bash
   aegis plugin doctor claude
   ```

## Install through local marketplace

If your Claude Code version supports repo-local marketplace files, see `integrations/claude-marketplace/` for a documented example catalog. The exact marketplace schema depends on the Claude Code version you are using.

## Verify install

Run the Aegis plugin doctor:

```bash
aegis plugin doctor claude
```

Expected output sections:
- Aegis version
- Policy status (present/valid)
- Plugin directories (claude: found)
- Host binaries (claude: detected or not detected)

## Available skills

| Skill | Purpose |
|-------|---------|
| `doctor` | Check Aegis installation, policy, and plugin readiness |
| `init` | Create or repair an Aegis policy for the current repo |
| `protect` | Explain how to run Claude Code under Aegis protection |
| `redteam` | Run deterministic red-team fixtures |
| `replay` | Show and explain the latest Aegis session replay |

Skills are invoked as `/aegis:doctor`, `/aegis:init`, `/aegis:protect`, `/aegis:redteam`, `/aegis:replay` depending on the Claude Code plugin namespace configuration.

## Hooks included

The plugin registers lifecycle hooks that call `aegis hook claude <event>`:

| Event | When it fires |
|-------|---------------|
| `SessionStart` | At the start of a Claude Code session |
| `UserPromptSubmit` | When a user submits a prompt |
| `PreToolUse` | Before Claude Code invokes a tool |
| `PermissionRequest` | When Claude Code requests user permission |
| `PostToolUse` | After Claude Code finishes using a tool |
| `SessionEnd` | When the session ends |

## How hooks call Aegis

Each hook sends a JSON payload to `aegis hook claude <event>` via stdin and reads a JSON decision from stdout. The hook stdout remains valid for Claude Code parsing. Human-readable logs go to stderr.

Example:

```bash
echo '{"version":1,"host":"claude","event":"PreToolUse","payload":{"tool":"shell","command":"git status"}}' \
  | aegis hook claude PreToolUse
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

Remove the plugin from Claude Code using your Claude Code plugin management commands. This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory; they do not enforce policy independently of the host.
- The strongest protection remains `aegis run -- <claude-code-command>`.
- Plugin installation preview only; actual host plugin loading depends on Claude Code version.
- No telemetry is collected.
- Official marketplace availability is not yet implemented.

## Security model

- This plugin calls the Aegis CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than Claude Code hooks support.

## No MCP server behavior

This plugin does not add MCP server behavior or drone-specific plugin features.

## Strongest protection warning

> The Aegis Claude Code plugin adds native skills and lifecycle hooks for Claude Code. For the strongest local protection, run the Claude Code process itself through Aegis with `aegis run -- <claude-code-command>`.
