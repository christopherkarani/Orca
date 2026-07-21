# Replay

Orca writes per-session artifacts under `.orca/sessions/<session-id>/`.

## Files

- `events.jsonl`: deterministic security events.
- `summary.json`: machine-readable session summary.
- `summary.md`: human-readable summary.
- `.orca/last`: pointer to the last session.

## Commands

Bare `orca replay` loads the **last** session and highlights denied actions. No sessions yet → friendly empty state pointing at Safe Launch (`orca start` then `orca <agent>`).

```sh
./zig-out/bin/orca replay
./zig-out/bin/orca replay --json
./zig-out/bin/orca replay --only denied
./zig-out/bin/orca replay --verify
./zig-out/bin/orca replay --tui
./zig-out/bin/orca replay --session <id>
./zig-out/bin/orca replay --list
```

## Alt-screen timeline

`--tui` opens the replay timeline in an interactive alt-screen view for terminals that support rich output. It is opt-in; the default replay output stays linear for logs and copy/paste. `--tui` is TTY-only and cannot be combined with `--json` because replay JSON is a frozen machine contract.

## Hash-chain Verification

Each event includes previous and current hashes. `--verify` detects modified, deleted, reordered, or malformed events and summary hash mismatches.

## Redaction

Secret-like values are redacted before persistence, not only during replay. Replay should not be used as a raw terminal transcript.
