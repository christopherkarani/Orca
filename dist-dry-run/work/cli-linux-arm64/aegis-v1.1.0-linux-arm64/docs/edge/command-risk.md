# Edge Command Risk

Edge command decisions use the shared Core result vocabulary: `allow`, `ask`, `deny`, and `observe`.

Risk classes:

- `low`: telemetry and state reads.
- `medium`: low-impact control-like commands such as hold.
- `high`: arm, takeoff, waypoint, velocity, altitude, mode, and mission commands.
- `critical`: disabling safety controls, raw actuator output, operator override, payload release, and firmware update.
- `emergency_safe`: `land` and `return_to_home`, still logged and safety-checked.
- `unknown`: fail-closed.

Decision rules:

- Explicit deny beats allow and ask.
- Explicit allow still requires safety constraints to pass.
- Explicit ask requires approval; CI and non-interactive mode convert ask to deny.
- Critical commands default to deny.
- `disable_failsafe`, `disable_geofence`, `raw_actuator_output`, `override_operator`, and `firmware_update` default to deny.
- `payload_release` defaults to deny unless explicitly configured for simulation/bench policy work. It is never assumed safe.

