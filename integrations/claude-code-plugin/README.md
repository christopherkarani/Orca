# Orca Claude Code Plugin

Orca safety hooks and skills for Claude Code.

## What this plugin does

This plugin adds Orca-native skills and lifecycle hooks to Claude Code. It lets Claude Code call the Orca CLI for policy checks, red-team fixtures, session replay, and runtime safety decisions without duplicating policy logic.

The plugin is a thin integration layer. The Orca CLI remains the source of truth for all policy decisions.

## Prerequisites

- Orca CLI built and available in PATH (or use `./zig-out/bin/orca` from the repo)
- Zig 0.15.2 to build Orca from source
- Claude Code host binary installed

## Install from local path

1. Build Orca:
   ```bash
   zig build
   ```

2. Install the plugin locally in Claude Code (method depends on Claude Code version; consult Claude Code docs for the latest plugin loading mechanism).

3. Verify the plugin is recognized:
   ```bash
   orca plugin doctor claude
   ```

## Install through local marketplace

If your Claude Code version supports repo-local marketplace files, see `integrations/claude-marketplace/` for a documented example catalog. The exact marketplace schema depends on the Claude Code version you are using.

## Verify install

Run the Orca plugin doctor:

```bash
orca plugin doctor claude
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (claude: found)
- Host binaries (claude: detected or not detected)

## Available skills

| Skill | Purpose |
|-------|---------|
| `doctor` | Check Orca installation, policy, and plugin readiness |
| `init` | Create or repair an Orca policy for the current repo |
| `protect` | Explain how to run Claude Code under Orca protection |
| `redteam` | Run deterministic red-team fixtures |
| `replay` | Show and explain the latest Orca session replay |

Skills are invoked as `/orca:doctor`, `/orca:init`, `/orca:protect`, `/orca:redteam`, `/orca:replay` depending on the Claude Code plugin namespace configuration.

## Hooks included

The plugin registers lifecycle hooks that call `orca hook claude <event>`:

| Event | When it fires |
|-------|---------------|
| `SessionStart` | At the start of a Claude Code session |
| `UserPromptSubmit` | When a user submits a prompt |
| `PreToolUse` | Before Claude Code invokes a tool |
| `PermissionRequest` | When Claude Code requests user permission |
| `PostToolUse` | After Claude Code finishes using a tool |
| `SessionEnd` | When the session ends |

## How hooks call Orca

Each hook sends a JSON payload to `orca hook claude <event>` via stdin and reads a JSON decision from stdout. The hook stdout remains valid for Claude Code parsing. Human-readable logs go to stderr.

Example:

```bash
echo '{"version":1,"host":"claude","event":"PreToolUse","payload":{"tool":"shell","command":"git status"}}' \
  | orca hook claude PreToolUse
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

Remove the plugin from Claude Code using your Claude Code plugin management commands. This plugin does not mutate host configuration, so uninstalling is safe.

## Known limitations

- Hooks are advisory; they do not enforce policy independently of the host.
- The strongest protection remains `orca run -- <claude-code-command>`.
- Plugin installation preview only; actual host plugin loading depends on Claude Code version.
- No telemetry is collected.
- Official marketplace availability is not yet implemented.

## Security model

- This plugin calls the Orca CLI; it does not reimplement policy logic.
- No raw secrets are persisted in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- This plugin does not claim stronger enforcement than Claude Code hooks support.

## No MCP server behavior

This plugin does not add MCP server behavior or drone-specific plugin features.

## Decision mapping (honest)

Orca returns host-actionable decisions on hook stdout. Claude Code interprets them:

| Orca | Expected host behavior |
|---|---|
| `allow` | Proceed |
| `block` | Deny the tool / permission |
| `ask` | Prefer Claude’s native permission / approval UI when the event supports it (`PermissionRequest` / gated tools). If the host surface cannot prompt, fail closed to deny — do not treat a model-visible note as approval. |
| `warn` | Advisory; do not silently equate to hard deny unless policy/CI requires it |

CI / noninteractive (`orca hook ... --ci` or env) hardens `ask` → `block` in Orca before the host sees it.

## Strongest protection warning

> The Orca Claude Code plugin adds native skills and lifecycle hooks for Claude Code. For the strongest local protection, run the Claude Code process itself through Orca with `orca run -- <claude-code-command>`.
