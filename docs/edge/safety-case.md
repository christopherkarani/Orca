# Edge Safety Case Reports

Phase 33 safety-case reports are customer-readable engineering evidence for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evaluation. They are not regulatory approval, certification, airworthiness approval, detect-and-avoid, autopilot replacement behavior, or real-flight readiness claims.

Generate a report:

```sh
aegis-edge safety-case generate \
  --scenario examples/edge/safety/scenarios/geofence-deny.yaml \
  --policy examples/edge/safety/policies/safety-strict.yaml
```

Outputs are written to `.aegis-edge/sessions/<session-id>/`:

- `events.jsonl`
- `summary.json`
- `summary.md`
- `safety-report.json`
- `safety-report.md`
- `final-hash.txt`
- `evidence/*`

Reports include metadata, policy hash, provenance, vehicle/adapter profile, scenario status, command evidence, safety findings, approvals, emergency decisions, traceability, limitations, and a non-certification disclaimer.

Fake success is not SITL success. SITL success is not real-flight success. Missing SITL is classified as skipped or unsupported, not passed.

Phase 34 red-team runs can generate run-scoped safety-case evidence:

```sh
aegis-edge redteam --report safety-case
```

The red-team safety report includes fixture results, expected and observed
decisions, safety findings, audit events, limitations, provenance, and the same
non-certification disclaimer. It links fixture outcomes to the run audit session
and replay artifact. Skipped, unsupported, and inconclusive fixtures are reported
honestly and never counted as passed.
