# protect

Explain how to run the current Claude Code workflow under Aegis protection.

## When to use

Use this skill when you want to ensure the current Claude Code session or command runs inside Aegis supervision.

## Strongest protection

The strongest local protection is running the Claude Code process itself through Aegis:

```bash
aegis run -- <claude-code-command>
```

If the exact Claude Code invocation is unknown, run the Claude Code CLI through Aegis using the command you normally use to start Claude Code.

## What the plugin provides

The Claude Code plugin adds:

- Native skills for doctor, init, protect, redteam, and replay.
- Lifecycle hooks that call `aegis hook claude <event>` for safety checks.

## Important limitation

> The Claude Code plugin adds native skills and lifecycle hooks. The strongest protection remains running the agent process through `aegis run`.

Hooks are advisory and additive. They do not replace the supervision that `aegis run` provides over the child process.

## Quick check

Verify Aegis is ready:

```bash
aegis plugin doctor claude
```

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- Hooks call the Aegis CLI; they do not duplicate policy logic.
