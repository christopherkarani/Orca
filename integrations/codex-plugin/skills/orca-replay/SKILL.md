# orca-replay

Show and explain the latest Orca session replay.

## When to use

Use this skill after running an Orca-protected session to review what happened, verify the audit log, and check for any policy violations or redactions.

## Commands

Replay the most recent session:

```bash
orca replay --session last
```

Replay with hash-chain verification:

```bash
orca replay --session last --verify
```

For machine-readable output:

```bash
orca replay --session last --json
```

## No session found

If no session exists, you will see an error like:

```
No sessions found in .orca/sessions/
```

To create a session, run a command through Orca first:

```bash
orca run -- echo hello
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
