# Technical Validation Call

## Purpose

Determine whether one tightly scoped Aegis Edge pilot can run in the customer's fake adapter, PX4 SITL, ArduPilot SITL, or no-actuation bench-preparation workflow.

## Stack Mapping

- Autonomy layer owner:
- Mission planner or agent:
- Command bridge:
- MAVLink/PX4/ArduPilot/ROS2/MAVROS/custom:
- Companion computer:
- Simulator:
- Existing logs:

## MAVLink Message/Command Surface

- Commands issued today:
- Mission upload path:
- Mode changes:
- Arm/disarm:
- LAND/RTH:
- Parameter changes:
- Custom messages:
- Unsupported commands:

## Coordinate Frames And Altitude

- Coordinate frames used:
- Altitude reference:
- Home position source:
- Geofence source:
- Known frame conversion risks:

## SITL Setup

- PX4 SITL available:
- ArduPilot SITL available:
- Fake adapter acceptable:
- CI integration:
- Required sample logs:
- No-actuation bench path:

## Policy Scope

- Geofence:
- Altitude:
- Velocity:
- Battery:
- Telemetry freshness:
- Operator approval:
- Emergency behavior:
- Data/telemetry egress:
- Runtime health:

## Adapter Needs

- Supported bridge:
- Custom mapping required:
- Data fields needed:
- Commands out of scope:
- Integration owner:

## Data/Telemetry Concerns

- Sensitive telemetry:
- Mission data:
- Location precision:
- Customer endpoint allowlist:
- Redaction expectations:
- No raw secrets required:

## Pilot Deliverables

- Command surface inventory.
- Policy baseline.
- Scenario list.
- Red-team scorecard.
- Safety-case report.
- Audit/replay evidence.
- Known limitations.
- Next-step integration plan.

## Integration Risks

- No simulator access.
- Custom messages dominate command surface.
- Unclear coordinate frames.
- Unavailable logs.
- Expectations outside customer-evaluation scope.
