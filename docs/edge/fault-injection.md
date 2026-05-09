# Edge Fault Injection

Phase 34 fault injection is simulation-only. Faults mutate synthetic state,
synthetic command requests, synthetic mission uploads, synthetic approvals,
synthetic emergency decisions, or synthetic MAVLink-like bytes. The suite does
not provide real-world drone attack procedures and does not require real
hardware or external network access.

Fault-injection evidence is not real-flight readiness, certification,
detect-and-avoid, autopilot replacement behavior, or regulatory approval.

Supported fault groups:

- State faults: stale or expired position, stale or unknown battery, invalid GPS, poor GPS accuracy, missing home position, unknown mode, unknown control authority, low or critical battery, and current position outside geofence.
- Command faults: waypoint outside geofence, altitude floor/ceiling violations, velocity violations, unknown command, critical command, disabling failsafe/geofence, raw actuator output, operator override, payload release, and firmware update.
- Mission faults: item outside geofence, altitude violation, partial upload, duplicate item, missing item, unsupported item, and mission start without a safe mission record.
- MAVLink faults: malformed, truncated, oversized, bad checksum, unknown message or command id, unexpected endpoint, replay/duplicate markers, signing limitation markers, and fake-secret payload markers.
- Approval faults: expired approval, mismatched policy/command/vehicle/state hashes, reused one-time approval, broad approval disallowed, and non-overridable command approval attempts.
- Emergency faults: attempts to disable failsafe or use raw actuator output, RTH without home, LAND on stale state when policy disallows it, operator override attempts, and no safe fallback.

The runner reuses the Edge safety evaluator, mission evaluator, operator
approval validation, emergency evaluator, MAVLink parser/gateway, Core redaction,
and Edge audit/replay paths. It does not duplicate policy, audit, or report
engines.
