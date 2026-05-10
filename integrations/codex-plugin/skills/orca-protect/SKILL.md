# orca-protect

Explain how to run the current Codex workflow under Orca protection.

## When to use

Use this skill when you want to ensure the current Codex session or command runs inside Orca supervision.

## Strongest protection

The strongest local protection is running the Codex process itself through Orca:

```bash
orca run -- <codex-command>
```

If the exact Codex invocation is unknown, run the Codex CLI through Orca using the command you normally use to start Codex.

## What the plugin provides

The Codex plugin adds:

- Native skills for doctor, init, protect, redteam, and replay.
- Lifecycle hooks that call `orca hook codex <event>` for safety checks.

## Important limitation

> The Codex plugin adds native skills and lifecycle hooks. The strongest protection remains running the agent process through `orca run`.

Hooks are advisory and additive. They do not replace the supervision that `orca run` provides over the child process.

## Quick check

Verify Orca is ready:

```bash
orca plugin doctor codex
```

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- Hooks call the Orca CLI; they do not duplicate policy logic.
