# Geofence Deny Safety Report

Provenance: fake_adapter
Scenario: geofence-deny
Decision: deny
policy_hash: sha256:example-geofence-policy-hash
Audit references: event-0001 edge.session_start, event-0002 safety.geofence_violation, event-0003 safety_case.generated
Replay verified: true

## Findings

- Command requested a waypoint outside the configured circular geofence.
- Safety evaluator denied the request.
- No command was sent to hardware or an external endpoint.

## Limitations

This is simulation/SITL/bench-preparation evidence only. It is a non-certification example and does not prove real-world flight safety.
