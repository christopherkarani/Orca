# Edge Safety Case Reports

Phase 33 safety-case reports are customer-readable engineering evidence for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evaluation. They are not regulatory approval, certification, airworthiness approval, or real-flight readiness claims.

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
