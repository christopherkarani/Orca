# Drone Safety for Plugins

> Scope: P01 — Drone-aware safety reporting in the Aegis CLI plugin surface
> Version: 1.1.0

## Detection

The Aegis CLI plugin surface detects the drone workstream by checking for:
- `packages/edge/` directory (Aegis Edge source)
- `aegis-edge` binary in PATH

When detected, `aegis plugin doctor` reports:

```
Drone workstream:
  detected: yes
  safety mode: plugin default-deny for live-control patterns
  simulation demos: allowed
  live control: requires explicit policy and human approval
```

## Safety-Critical Categories

The following categories are classified as safety-critical and are default-deny in any plugin context:

| Category | Risk Level |
|----------|------------|
| Arming / disarming | Critical |
| Takeoff / landing | Critical |
| Motor or actuator commands | Critical |
| Mission upload | High |
| Navigation commands | High |
| Live vehicle connection | High |
| Flight-critical parameter changes | Critical |

## Plugin Restrictions

### Simulation-Only Demos

All plugin demos involving drone behavior must use deterministic fake adapters or clearly labeled simulation fixtures:

- Fake MAVLink transport is the default.
- Fake-PX4 and fake-ArduPilot are the default paths.
- PX4 SITL and ArduPilot SITL are opt-in only and require explicit environment variables.

### Live Control Default-Deny

- Plugins must not expose tools that send commands to real vehicles.
- Plugins must not open real serial, UDP, or TCP MAVLink endpoints without explicit human opt-in.
- Plugins must not bypass the safety evaluator or approval system.

### Test Preservation

- All existing drone tests must continue to pass.
- No plugin work may delete, skip, or weaken Edge red-team fixtures.
- No plugin work may change the default fail-closed behavior of the safety evaluator.

## No Operational Instructions

This document does not contain operational drone-control instructions. It defines safety categories and plugin restrictions only.

For Edge-specific operational details, see the Edge documentation in `docs/edge/`.

## See Also

- `docs/integrations/orca-cli-plugin.md`
- `docs/integrations/plugin-security-model.md`
- `docs/integrations/drone-safepoint.md`
