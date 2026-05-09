# aegis-protect

Explain how to run the current Codex workflow under Aegis protection.

## When to use

Use this skill when you want to ensure the current Codex session or command runs inside Aegis supervision.

## Strongest protection

The strongest local protection is running the Codex process itself through Aegis:

```bash
aegis run -- <codex-command>
```

If the exact Codex invocation is unknown, run the Codex CLI through Aegis using the command you normally use to start Codex.

## What the plugin provides

The Codex plugin adds:

- Native skills for doctor, init, protect, redteam, and replay.
- Lifecycle hooks that call `aegis hook codex <event>` for safety checks.

## Important limitation

> The Codex plugin adds native skills and lifecycle hooks. The strongest protection remains running the agent process through `aegis run`.

Hooks are advisory and additive. They do not replace the supervision that `aegis run` provides over the child process.

## Quick check

Verify Aegis is ready:

```bash
aegis plugin doctor codex
```

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- Hooks call the Aegis CLI; they do not duplicate policy logic.
