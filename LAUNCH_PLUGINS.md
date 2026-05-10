# Orca Plugins — Launch Announcement

Orca 1.1.0 now ships native plugin integrations for Codex, Claude Code, and OpenCode. The launch is deliberately small and local: the plugins add host-native skills and lifecycle hooks that call the Orca CLI for policy decisions, red-team checks, replay, and plugin diagnostics.

## What Orca plugins are

Orca plugins are native integrations for supported agent hosts. They let Codex, Claude Code, and OpenCode surface Orca commands, hook events, and install flows without duplicating policy logic inside the host.

## Why they exist

Agent-host skills and lifecycle hooks call the Orca CLI so the same policy engine can make the decision, emit the audit trail, and support replay later. That keeps the plugin layer thin and honest about its limits.

## Suggested positioning

> Orca now has native plugin integrations for Codex, Claude Code, and OpenCode. The plugins add agent-host skills and lifecycle hooks that call the Orca CLI for policy decisions, red-team checks, replay, and plugin diagnostics.

## Codex plugin summary

- Path: `integrations/codex-plugin/`
- Manifest: `.codex-plugin/plugin.json`
- Skills: `aegis-doctor`, `aegis-init`, `aegis-protect`, `aegis-redteam`, `aegis-replay`
- Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop`
- Install guide: [docs/integrations/codex.md](docs/integrations/codex.md)

## Claude Code plugin summary

- Path: `integrations/claude-code-plugin/`
- Manifest: `.claude-plugin/plugin.json`
- Skills: `doctor`, `init`, `protect`, `redteam`, `replay`
- Hooks: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionEnd`
- Install guide: [docs/integrations/claude-code.md](docs/integrations/claude-code.md)

## OpenCode plugin summary

- Path: `integrations/opencode-plugin/`
- Main file: `orca.ts`
- Hooks: `session.created`, `tool.execute.before`, `tool.execute.after`, `permission.asked`, `permission.replied`, `file.edited`, `command.executed`, `session.updated`, `session.idle`, `session.error`, `shell.env`
- Install guide: [docs/integrations/opencode.md](docs/integrations/opencode.md)

## OpenClaw plugin summary

- Path: `integrations/openclaw-plugin/`
- Manifest: `openclaw.plugin.json`
- Package: `package.json`
- Hooks: `session.start`, `tool.before`, `tool.after`, `permission.before`, `permission.after`, `session.end`
- Install guide: [docs/integrations/openclaw.md](docs/integrations/openclaw.md)

## Install links

- Codex: [docs/integrations/codex.md](docs/integrations/codex.md)
- Claude Code: [docs/integrations/claude-code.md](docs/integrations/claude-code.md)
- OpenCode: [docs/integrations/opencode.md](docs/integrations/opencode.md)
- OpenClaw: [docs/integrations/openclaw.md](docs/integrations/openclaw.md)

## Repo marketplace install

**Codex:**
```bash
codex plugin marketplace add YOUR_ORG/orca
```
Then install Orca from Codex's plugin UI/directory after adding the marketplace.

**Claude Code:**
```bash
claude plugin marketplace add YOUR_ORG/orca
claude plugin install orca@orca --scope user
```

Or inside Claude Code:
```text
/plugin marketplace add YOUR_ORG/orca
/plugin install orca@orca
/reload-plugins
```

These commands add the Orca repository as a plugin marketplace source. This is not the same as being listed in the official Codex or Claude marketplace. Official marketplace availability is a separate process; repo marketplace support is available now.

## Demo flow

See [examples/plugin-demo/](examples/plugin-demo/) for a local demo flow. A reasonable sequence is:

1. Install the plugin from a release artifact or local path.
2. Run `aegis plugin doctor <host>`.
3. Check the manifest with `aegis plugin manifest <host>`.
4. Run a hook smoke test.
5. Replay the latest session with `orca replay --session last --verify`.

## Limitations

- Hooks are advisory and depend on host support.
- Official marketplace availability is not yet implemented.
- OpenClaw npm package is planned in P10; ClawHub submission is planned in P11.
- Plugin installation defaults to preview/dry-run.
- No telemetry, SaaS, or remote control plane is added.
- These plugins do not add MCP server functionality or drone-specific plugin features.
- The plugins do not protect sessions launched outside Orca.

## Security model

The strongest protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

## Contribution ask

Please try the plugins, verify the docs against real host behavior, and send fixes for edge cases, install friction, or wording that reads more optimistic than the implementation deserves.

## Issue reporting instructions

- Security issues: report privately through [SECURITY.md](SECURITY.md).
- Bugs and docs issues: open a GitHub issue with the host version, the relevant `aegis plugin doctor <host> --json` output, and the exact reproduction steps.
- Do not include real secrets or private logs.

## Launch post drafts

### GitHub release

> Orca 1.1.0 adds native plugin integrations for Codex, Claude Code, OpenCode, and OpenClaw. The plugins surface Orca skills and lifecycle hooks that call the CLI for policy decisions, red-team checks, replay, and diagnostics. Installation is local and verifiable; hooks remain advisory, and the strongest protection still comes from `orca run`.

### Hacker News / Reddit

> Orca now has native plugin integrations for Codex, Claude Code, OpenCode, and OpenClaw. The point is not magic enforcement — it is a thin local plugin layer that calls the Orca CLI for policy, replay, and diagnostics while staying honest about host limits.

### X / LinkedIn

> Orca 1.1.0 ships native plugin integrations for Codex, Claude Code, OpenCode, and OpenClaw. The plugins add agent-host skills and lifecycle hooks that call the Orca CLI for policy decisions, red-team checks, replay, and plugin diagnostics.

### Developer / security communities

> Orca 1.1.0 adds host-native plugin integrations for Codex, Claude Code, OpenCode, and OpenClaw. The plugin layer stays local, uses the Orca CLI as the source of truth, and keeps the strongest protection rooted in `orca run` rather than pretending the host extension layer is a sandbox.
