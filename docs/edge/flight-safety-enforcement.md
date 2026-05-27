# Flight Safety Enforcement

Phase 31 adds a reusable Edge safety layer for fake-adapter, PX4 SITL, and ArduPilot SITL contexts. The public API is `edge.safety.evaluateSafety(policy, vehicle_state, command_request, context)` and mission uploads use `edge.safety.evaluateMissionSafety(...)`.

The evaluator returns a Core decision (`allow`, `ask`, `deny`, or `observe`), structured safety findings, violated constraints, matched rules, a risk score, recommended fallback, operator-approval-required metadata, CI proceedability, prepared audit events, and a human explanation. It never forwards commands. MAVLink, PX4, and ArduPilot paths call the evaluator and then decide whether to forward or block according to gateway mode.

Implemented checks:

- command risk defaults and deny priority
- circular geofence
- altitude floor and ceiling
- horizontal and vertical velocity limits
- battery thresholds and stale/unknown battery handling
- stale, expired, and unknown vehicle state handling
- mode and control-authority handling
- mission waypoint safety and duplicate/missing item detection

Modes:

- `observe`: records findings while gateway observe semantics can still forward.
- `ask`: returns `ask` for policy-approved high-risk commands.
- `strict`: denies unapproved or unsafe high-risk commands.
- `ci` and `redteam`: non-interactive; `ask` becomes `deny`.
- `simulation` and `bench`: decision evidence only; no hardware operation.

Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval, and not real-flight readiness.
