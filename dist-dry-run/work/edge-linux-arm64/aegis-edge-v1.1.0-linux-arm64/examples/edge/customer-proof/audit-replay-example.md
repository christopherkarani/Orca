# Audit Replay Example

Provenance: fake_adapter
policy_hash: sha256:example-replay-policy-hash

```text
Replay verified: true
Session: example-geofence-deny
Final hash: sha256:example-final-hash
Events:
  event-0001 edge.session_start
  event-0002 safety.geofence_violation
  event-0003 safety_case.generated
```

## Limitations

This is simulation/SITL/bench-preparation evidence only. It is a non-certification example and does not prove real-world flight safety.
