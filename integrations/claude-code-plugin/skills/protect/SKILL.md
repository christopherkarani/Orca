# protect

Explain how to run the current Claude Code workflow under Orca protection.

## When to use

Use this skill when you want to ensure the current Claude Code session or command runs inside Orca supervision.

## Strongest protection

The strongest local protection is running the Claude Code process itself through Orca:

```bash
orca run -- <claude-code-command>
```

If the exact Claude Code invocation is unknown, run the Claude Code CLI through Orca using the command you normally use to start Claude Code.

## What the plugin provides

The Claude Code plugin adds:

- Native skills for doctor, init, protect, redteam, and replay.
- Lifecycle hooks that call `orca hook claude <event>` for safety checks.

## Important limitation

> The Claude Code plugin adds native skills and lifecycle hooks. The strongest protection remains running the agent process through `orca run`.

Hooks are advisory and additive. They do not replace the supervision that `orca run` provides over the child process.

## Quick check

Verify Orca is ready:

```bash
orca plugin doctor claude
```

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- Hooks call the Orca CLI; they do not duplicate policy logic.
