# Degraded Modes

Degraded modes are conservative command filters applied after health findings are aggregated. Supported behaviors include `observe_only`, `deny_high_risk`, `deny_movement`, `deny_external_egress`, `fail_closed`, `allow_emergency_land_only`, `allow_policy_emergency_only`, and `no_safe_action`.

`disable_failsafe`, `disable_geofence`, `raw_actuator_output`, and `override_operator` remain denied by default. RTH requires a valid home position. HOLD requires a valid position/control context. CI mode never prompts.

Degraded mode is not real-flight readiness, does not replace autopilot failsafes, is not an autopilot replacement, and is not regulatory certification.
