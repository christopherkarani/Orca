# Operator Approval

Edge Phase 32 supports local, bounded operator approval records for fake-adapter, PX4 SITL, ArduPilot SITL, simulation, and bench-preparation evaluation.

An approval request binds the vehicle id, command id, command type, command request hash, policy hash, state snapshot hash, safety evaluation hash, safety constraints hash, provenance, expiry, requested scope, risk class, matched policy rule, and findings summary. The default scope is `exact_action_only` with `max_uses: 1`.

Approval lifecycle:

1. A policy decision returns `ask` or `require_operator_approval`.
2. Interactive simulation or bench contexts can create an approval request.
3. A decision can approve or deny the request.
4. Validation checks expiry, revocation, use count, vehicle, policy, state, safety constraints, command hash, provenance, scope, and operator identity.
5. A valid approval can turn an `ask` result into `allow`.

Approval cannot override a safety-envelope deny by default. It also cannot make `disable_failsafe`, `disable_geofence`, `raw_actuator_output`, or `override_operator` safe by default.

Fake, PX4, and ArduPilot scenario files may include a bounded `approval:` seed such as `valid_once`, `expired`, `mismatched_policy`, `mismatched_command`, `broad_command_type`, `revoked`, or `reused_once`. These seeds are deterministic local fixtures for exercising the same validation code used by the safety evaluator and gateway; they are not long-term authorization records.

This feature is local-only and not a cloud approval system, SaaS approval system, SSO/RBAC system, mobile app, regulatory approval, real-flight validation, detect-and-avoid capability, autopilot replacement, or flight controller.
