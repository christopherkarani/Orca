# Aegis Edge Safety Policy

Phase 27 implements local Edge policy evaluation. Phase 28 adds MAVLink fake-transport protocol mediation on top of that policy engine. Phase 29 adds deterministic fake-PX4 scenarios and opt-in PX4 SITL simulation evidence. It validates policy files and evaluates fake/simulation/bench command requests against vehicle state. It does not enforce flight safety, mediate real drone hardware commands, or integrate ArduPilot, ROS2, customer hardware, or real hardware. Aegis Edge is not ready for real flight and must not be used for real flight.

## Safety Envelope

The safety envelope supports:

- state freshness constraints
- circular WGS84 geofence constraints
- altitude limits with explicit altitude reference
- horizontal and vertical velocity limits
- battery thresholds
- command allow, ask, and deny lists
- network mode metadata
- emergency-safe policy defaults for local decisions
- audit settings

Policy evaluation returns a Core decision plus findings, violated constraints, matched rules, recommended fallback actions, prepared audit events, and an explanation string.

## Validation Rules

Validation rejects missing version, unknown strict vehicle/autopilot/adapter values, invalid latitude/longitude, unknown altitude references, invalid geofence radius, unsupported geofence shapes, max altitude below min altitude, invalid velocity limits, invalid battery thresholds, inconsistent battery thresholds, duplicate command entries, ambiguous stale-state policy, invalid network settings, invalid audit settings, and unknown emergency defaults.

Deny priority is fail-closed: an explicit `deny` wins over allow or ask. Duplicate command entries are invalid so policy authors cannot hide conflicts.

## Safety Boundary

Stale, expired, unknown, or ambiguous state is unsafe. Emergency `land` may proceed on stale state only when policy explicitly allows it and `land` is not denied. `return_to_home` may proceed on stale state only when policy explicitly allows it and a home position is available. These are policy decisions and recommendations only; no emergency runtime behavior is triggered.

Fake adapter state must remain fake. MAVLink fake transport must remain labeled `fake_transport` or `fake_transport/simulation`. Fake-PX4 state remains `fake_adapter`; opt-in PX4 SITL state is `sitl_px4`. Simulation examples are not flight validation.
