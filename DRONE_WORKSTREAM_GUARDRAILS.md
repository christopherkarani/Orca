# Drone Workstream Guardrails

> Version: 1.1.0
> Status: Active

## Purpose

This document defines guardrails for drone-related work in the Aegis plugin surface. It ensures that plugin functionality does not accidentally expose live drone controls or weaken existing safety mechanisms.

## Guardrails

### 1. Default-Deny for Live Control

All live drone control patterns are default-deny in plugin context:

- Arming / disarming
- Takeoff / landing
- Motor or actuator commands
- Mission upload
- Navigation commands
- Live vehicle connection
- Flight-critical parameter changes

### 2. Simulation-Only Demos

Plugin demos must use:
- Fake MAVLink transport
- Fake-PX4 or fake-ArduPilot adapters
- Deterministic simulation fixtures

SITL is opt-in only and requires explicit environment variables.

### 3. No Real-Flight Claims

Plugins must not claim:
- Real-flight readiness
- Certification
- Detect-and-avoid capability
- Autopilot replacement

### 4. Test Preservation

- All existing drone tests must continue to pass.
- No plugin work may delete, skip, or weaken Edge red-team fixtures.
- No plugin work may change the default fail-closed behavior.

### 5. No Operational Instructions

Plugin documentation must not contain operational drone-control instructions. Safety categories and restrictions only.

## Enforcement

These guardrails are enforced by:
- Code review for any plugin change touching drone-related code
- CI checks that run `aegis-edge redteam --ci`
- Static analysis for live-control pattern exposure

## See Also

- `docs/integrations/drone-safety.md`
- `docs/integrations/drone-safepoint.md`
