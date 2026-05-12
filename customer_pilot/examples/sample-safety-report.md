# Sample Safety Report

Example data only. Customer placeholder: ExampleCo Robotics. Environment: fake adapter. This is not real flight.

## Metadata

- Aegis Edge version: example-local
- Policy hash: `sha256:example-policy-hash`
- Scenario hash: `sha256:example-scenario-hash`
- Evidence source: fake adapter

## Scenario

An autonomy planner requests a waypoint outside the configured geofence.

## Result

- Decision: deny.
- Reason: waypoint outside geofence.
- Audit/replay: verified in example replay output.

## Findings

- Unsafe command denied.
- Emergency LAND remained available according to policy in a separate scenario.
- No external network was required.

## Limitations

- fake adapter evidence only.
- PX4 SITL and ArduPilot SITL not run in this sample.
- Bench-preparation not run in this sample.
- non-certification customer-evaluation evidence.
- not real flight.
