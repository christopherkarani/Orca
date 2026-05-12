# Traceability Matrix Example

Provenance: fake_adapter
policy_hash: sha256:example-traceability-policy-hash

| Requirement | Evidence | Audit Reference | Status |
| --- | --- | --- | --- |
| Deny waypoint outside geofence | geofence-deny-safety-report.md | event-0002 | passed |
| Replay evidence | audit-replay-example.md | final hash | passed |
| Redaction before persistence | data-exfil-deny-report.md | event-0301 | passed |

## Limitations

This is simulation/SITL/bench-preparation evidence only and a non-certification example.
