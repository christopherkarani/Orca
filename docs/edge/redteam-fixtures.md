# Edge Red-Team Fixtures

Fixtures live under `examples/edge/redteam/**/fixture.yaml`.

Fixtures are synthetic engineering evidence only. They are not real-flight
readiness, certification, detect-and-avoid, autopilot replacement behavior, or
regulatory approval.

Version 1 fields:

```yaml
version: 1
id: geofence-waypoint-outside-circular-denied
name: Waypoint outside circular geofence denied
category: geofence
environment: fake_adapter
description: Synthetic command requests a waypoint outside the configured geofence.
policy: examples/edge/redteam/policies/redteam-envelope.yaml
state: examples/edge/safety/states/fresh-state.json
request: examples/edge/safety/requests/waypoint-outside-geofence.json
faults:
  - waypoint_outside_geofence
expected:
  status: passed
  decision: deny
  findings:
    - geofence
  events:
    - safety.geofence_violation
  no_log_contains:
    - fake-secret-value
requirements:
  px4_sitl: false
  ardupilot_sitl: false
  real_hardware: false
  capabilities:
    - fake_adapter
skip_conditions:
  - none
limitations:
  - simulation evidence only
score:
  points: 10
```

Supported categories are `geofence`, `altitude`, `velocity`, `battery`,
`stale_state`, `mission`, `mavlink_parser`, `mavlink_command`,
`endpoint_spoofing`, `approval_bypass`, `emergency_bypass`, `mode_authority`,
`telemetry_fault`, `px4_sitl`, `ardupilot_sitl`, `audit_redaction`,
`safety_case`, and `unsupported_feature`.

Supported environments are `fake_adapter`, `fake_px4_adapter`,
`fake_ardupilot_adapter`, `px4_sitl`, and `ardupilot_sitl`.

Fixture validation rejects real-hardware requirements. Required fixtures should
be deterministic and should include forbidden-log checks for fake secret markers.
