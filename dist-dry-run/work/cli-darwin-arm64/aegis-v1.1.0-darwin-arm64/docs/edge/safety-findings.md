# Safety Findings

Safety findings are structured records attached to safety evaluations.

Fields include:

- finding ID
- category
- severity
- command ID
- vehicle ID
- constraint ID
- observed value
- limit value
- frame/reference/unit
- decision
- explanation
- timestamp
- provenance
- audit event reference

Categories are `geofence`, `altitude`, `velocity`, `battery`, `stale_state`, `mode_constraint`, `authority_constraint`, `command_risk`, `mission`, `endpoint`, `unsupported`, and `unknown`.

Severity is `info`, `warning`, `high`, or `critical`.

Prepared safety audit events include `safety.evaluation_started`, `safety.evaluation_completed`, `safety.finding_created`, violation events, and vehicle command allow/deny/observe events. Payloads are bounded and redacted before persistence.
