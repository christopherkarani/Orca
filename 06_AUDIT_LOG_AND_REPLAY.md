# Phase 06 — Audit Log and Replay

## Objective

Implement persistent audit logging and session replay.

At the end of this phase, every `aegis run` session should create a session directory, write JSONL events, maintain a tamper-evident hash chain, write a summary, and support `aegis replay`.

---

## Scope

Implement:

- Session directory creation.
- `events.jsonl`.
- `summary.json`.
- `summary.md`.
- Event serialization.
- Event hash chain.
- Basic redaction hook.
- `aegis replay`.
- `aegis replay --session last`.
- `aegis replay --json`.
- `aegis replay --only denied`.
- Session index or `last` pointer.

---

## Non-goals

Do not implement full secret redaction yet. Add a redaction hook that later phases can fill.

Do not implement policy enforcement yet.

---

## Session Directory Layout

```text
.aegis/
  sessions/
    2026-05-05T12-15-30Z_8f1c/
      events.jsonl
      summary.json
      summary.md
  last
```

The `last` file can contain the latest session ID.

---

## Event Format

Use JSON Lines. Example:

```json
{
  "version": 1,
  "session_id": "2026-05-05T12-15-30Z_8f1c",
  "event_id": "evt_000001",
  "timestamp": "2026-05-05T12:15:30.000Z",
  "type": "session_start",
  "actor": {
    "process": "aegis"
  },
  "target": {
    "command": "echo"
  },
  "decision": null,
  "previous_hash": null,
  "event_hash": "..."
}
```

Use stable/canonical serialization for the hash input. If full canonical JSON is too large for this phase, implement deterministic field ordering for Aegis events.

---

## Hash Chain

Each event hash should be:

```text
event_hash = SHA256(previous_hash || canonical_event_without_event_hash)
```

If the Zig standard library hash function is used, keep code simple and testable.

Add:

```bash
aegis replay --verify
```

If verification fails, print a clear warning and non-zero exit.

---

## Replay Output

Human-readable replay:

```text
Session: 2026-05-05T12-15-30Z_8f1c
Command: echo hello
Policy: none
Status: exit 0

12:15:30  session_start
12:15:30  process_launch     echo hello
12:15:30  session_exit       exit 0

Hash chain: verified
```

JSON replay should emit either the raw JSONL or a JSON array.

---

## Events to Emit in This Phase

- `session_start`
- `process_launch`
- `session_exit`

Later phases will add policy, file, command, network, MCP, and secret events.

---

## Tests

Add tests for:

- Session directory creation.
- Event JSONL writing.
- Hash chain verification.
- Replay human output.
- Replay JSON output.
- Tamper detection.
- `last` session resolution.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Running `aegis run -- echo hello` creates `.aegis/sessions/<id>/events.jsonl`.
- `aegis replay --session last` prints the session timeline.
- `aegis replay --verify` verifies the hash chain.
- Manually tampering with an event causes verification failure.
- Logs do not include raw secret redaction yet, but the API path for redaction exists.

---

## Codex Execution Prompt

```text
Implement Phase 06: Audit Log and Replay.

Add persistent JSONL audit logs, session directories, session summaries, a hash chain, and `aegis replay`. Emit session_start, process_launch, and session_exit events from `aegis run`. Add verification and tests.

Run:
- zig build
- zig build test
- manual smoke test: aegis run -- echo hello
- manual smoke test: aegis replay --session last --verify

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The policy engine will add decisions to events. Keep event serialization flexible enough for future event fields.


---

## Review Addendum — Audit Is a Security Boundary

The audit writer must be the only code path that persists events. It must redact before writing, even if Phase 08 later improves the redactor.

Codex must implement deterministic event field ordering for hash-chain input. If canonical JSON is simplified in this phase, document the exact deterministic serialization and add a test proving stable hashes for the same event.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
