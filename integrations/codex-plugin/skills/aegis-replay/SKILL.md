# aegis-replay

Show and explain the latest Aegis session replay.

## When to use

Use this skill after running an Aegis-protected session to review what happened, verify the audit log, and check for any policy violations or redactions.

## Commands

Replay the most recent session:

```bash
aegis replay --session last
```

Replay with hash-chain verification:

```bash
aegis replay --session last --verify
```

For machine-readable output:

```bash
aegis replay --session last --json
```

## No session found

If no session exists, you will see an error like:

```
No sessions found in .aegis/sessions/
```

To create a session, run a command through Aegis first:

```bash
aegis run -- echo hello
```

Then retry the replay command.

## What replay shows

- Session events (commands, file operations, network requests)
- Policy decisions (allow, block, ask, warn)
- Redacted fields (secrets removed before logging)
- Hash-chain verification status (tamper-evident audit)

## Notes

- This skill does not modify host configuration.
- No telemetry is sent.
- Replay reads local audit logs only; no external service is contacted.
