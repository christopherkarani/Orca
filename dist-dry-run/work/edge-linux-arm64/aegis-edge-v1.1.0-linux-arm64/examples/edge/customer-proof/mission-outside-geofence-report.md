# Mission Outside Geofence Report

Provenance: fake_adapter
Scenario: mission-outside-geofence
Decision: deny
policy_hash: sha256:example-mission-policy-hash
Audit references: event-0201 safety.mission_denied

## Findings

- Mission item violates geofence policy.
- Upload/start behavior remains blocked in the demo.

## Limitations

This is simulation/SITL/bench-preparation evidence only. It is a non-certification example and does not prove all customer mission formats are safe.
