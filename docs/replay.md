# Replay

Aegis writes per-session artifacts under `.aegis/sessions/<session-id>/`.

## Files

- `events.jsonl`: deterministic security events.
- `summary.json`: machine-readable session summary.
- `summary.md`: human-readable summary.
- `.aegis/last`: pointer to the last session.

## Commands

```sh
./zig-out/bin/aegis replay --session last
./zig-out/bin/aegis replay --session last --json
./zig-out/bin/aegis replay --session last --only denied
./zig-out/bin/aegis replay --session last --verify
```

## Hash-chain Verification

Each event includes previous and current hashes. `--verify` detects modified, deleted, reordered, or malformed events and summary hash mismatches.

## Redaction

Secret-like values are redacted before persistence, not only during replay. Replay should not be used as a raw terminal transcript.
