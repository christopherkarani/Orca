# Approval Scopes

The safest approval scope is `exact_action_only`. It binds one approval to one command request hash, one vehicle, one policy hash, one state snapshot hash, one safety constraints hash, one provenance label, one expiry, and one use by default.

Supported scope concepts:

- `exact_action_only`: default and recommended.
- `command_type`: broad; rejected unless policy explicitly allows broad scopes.
- `mission_id`: broad; rejected unless policy explicitly allows broad scopes.
- `scenario_id`: broad; rejected unless policy explicitly allows broad scopes.
- `vehicle_id`: broad; rejected unless policy explicitly allows broad scopes.
- `time_window`: broad; rejected unless policy explicitly allows broad scopes.

Broad approvals are dangerous because they can unintentionally cover changed command parameters, changed state, changed policy, changed safety constraints, or a changed provenance context. Edge rejects broad approval by default and still requires the safety envelope to pass.

Approvals must expire. `max_uses` defaults to `1` unless policy says otherwise. Policy changes, state changes, command parameter changes, provenance changes, expiry, revocation, and exhausted use counts invalidate approvals.
