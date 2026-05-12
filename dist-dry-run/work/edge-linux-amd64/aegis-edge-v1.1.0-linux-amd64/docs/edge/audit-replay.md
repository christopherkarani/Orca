# Edge Audit And Replay

Aegis Edge records Phase 33 evidence under `.aegis-edge/sessions/<session-id>/`.
The authoritative event log is `events.jsonl`, written through the Aegis Core audit writer. Edge does not maintain a second independent audit writer.

Each event is redacted before persistence and includes Core `previous_hash` and `event_hash` fields. `aegis-edge replay --session last --verify` verifies the same hash-chain rules used by the main `aegis replay` command, but reads `.aegis-edge` instead of `.aegis`.

Replay proves:

- which Edge events were recorded in order
- whether the hash chain and summary match
- commands that were allowed, denied, observed, approval-gated, forwarded, or blocked
- findings and matched policy evidence present in the session artifacts
- explicit fake/PX4 SITL/ArduPilot SITL/bench/unknown provenance

Replay does not prove:

- real-flight readiness
- regulatory approval or certification
- detect-and-avoid behavior
- autopilot replacement behavior
- hardware integration

Useful commands:

```sh
aegis-edge replay --session last --verify
aegis-edge replay --session last --json
aegis-edge replay --session last --findings
aegis-edge replay --session last --commands
aegis-edge replay --session last --approvals
aegis-edge replay --session last --safety-case
```
