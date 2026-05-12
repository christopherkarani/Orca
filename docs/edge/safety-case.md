# Edge Safety Case Reports

Phase 33 safety-case reports are customer-readable engineering evidence for fake-adapter, PX4 SITL, ArduPilot SITL, and bench-preparation evaluation. Phase 35 adds data guard evidence for telemetry/data policy, endpoint classification, egress decisions, redactions, and exfiltration findings. These reports are not regulatory approval, certification, airworthiness approval, detect-and-avoid, autopilot replacement behavior, or real-flight readiness claims.

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

Phase 35 reports also include a Data/Network Guard section and `evidence/data-network-guard.json`. That evidence summarizes observed data classes, observed endpoint labels/kinds, allowed/denied endpoint decisions, redactions applied, telemetry guard limitations, and proof that normal evidence generation does not require external network calls. Sensitive payload values are redacted before report persistence.

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
## Runtime Health Evidence

Phase 37 safety-case reports include runtime health status, watchdog policy summary, domain health statuses, heartbeat freshness, telemetry freshness, audit writer health, degraded-mode decisions, fail-closed events, health event references, and limitations where available.

Runtime health evidence is simulation/SITL/bench-preparation evidence only. It is not real-flight readiness, not an autopilot replacement, and not regulatory certification.
