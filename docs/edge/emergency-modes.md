# Emergency Modes

Edge Phase 32 evaluates emergency-mode decisions for fake-adapter, PX4 SITL, ArduPilot SITL, simulation, and bench-preparation contexts.

Supported emergency commands:

- `land`
- `return_to_home` / `return_to_launch`
- `hold_position`
- `stop_or_brake` when a supported simulated path exists
- `disarm` only when explicitly policy-supported and safe in context

Emergency reasons include low battery, critical battery, geofence violation, lost link, stale state, operator request, and policy violation.

Emergency mode is not a policy bypass. LAND, HOLD, and RTH are still evaluated against policy, state freshness, available position/home context, provenance, command risk, and authority constraints. Emergency mode never allows `disable_failsafe`, `disable_geofence`, `raw_actuator_output`, or `override_operator` by default.

Edge does not send real emergency commands to real hardware in this phase.
