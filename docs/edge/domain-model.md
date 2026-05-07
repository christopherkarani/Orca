# Aegis Edge Domain Model

Aegis Edge models vehicle state, command requests, safety envelopes, and audit/report schema inputs. It is a policy and audit runtime foundation for later phases. It is not ready for real flight and must not be used for real flight.

## Vehicle Profile

Vehicle identity and platform fields are explicit:

- `VehicleId`
- `VehicleKind`: multirotor, fixed wing, VTOL, ground robot, simulated vehicle, or unknown.
- `AutopilotKind`: PX4, ArduPilot, fake, custom, or unknown.
- `AdapterKind`: fake, MAVLink, ROS2, custom, or unknown.
- `VehicleMode`, `ArmState`, and `ControlAuthority`.

These are domain values only. They are not mapped to MAVLink, PX4, ArduPilot, ROS2, or hardware numeric IDs in Phase 27.

## Vehicle State

`VehicleState` preserves:

- vehicle profile and mode
- global and local position
- velocity, attitude, and heading
- battery, GPS, link, and sensor state
- control authority
- home position
- timestamp
- freshness
- provenance

Freshness is explicit: `fresh`, `stale`, `expired`, or `unknown`. Unknown state is not treated as safe. Fake adapter state must not be mislabeled as SITL, bench, or customer adapter state.

## Command Requests

`CommandRequest` is a validation and policy-evaluation input for later phases. It does not send commands anywhere.

Command categories are:

- read-only: telemetry, mission status, vehicle state, camera frame
- normal control: arm, disarm, takeoff, land, return-to-home, hold, waypoint, velocity, altitude, heading, mission operations
- sensitive/high-risk: geofence/failsafe changes, mode changes, operator override, raw actuator output, payload release, firmware update, reboot, external telemetry stream

Each command request carries command id, vehicle id, action, parameters, actor, timestamp, provenance, optional mission/correlation/operator approval ids, risk classification, and raw protocol reference placeholder.

## Risk Classification

Telemetry reads are low risk. Land and return-to-home are `emergency_safe` actions, still logged and safety-checked. Arm, takeoff, and mission actions are high risk. Disabling failsafe/geofence, raw actuator output, firmware update, and payload release are critical by default.
