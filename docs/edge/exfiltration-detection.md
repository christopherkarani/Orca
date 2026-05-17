# Edge Exfiltration Detection

Phase 35 adds deterministic data guard findings for suspicious simulated egress. The heuristics are intended for local safety evidence and regression testing, not for real-world offensive guidance.

Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

The detector flags:

- Long query strings.
- High-entropy endpoint labels.
- Base64-like payload fragments.
- Repeated unknown endpoint attempts.
- Direct public IP egress.
- Webhook, request-bin, paste, and tunnel endpoint kinds.
- Mission data sent to unknown or suspicious endpoints.
- Exact geolocation sent to unknown or suspicious endpoints.
- Video/image payloads sent to unknown or suspicious endpoints.
- Credential or secret-like patterns in telemetry payloads.
- MAVLink-like payloads sent outside explicit fake/SITL/ground-control endpoints.

Findings include category, severity, reason, endpoint kind, data class when available, decision, matched rule when available, and audit event reference. The audit stream uses events such as `data.exfiltration_suspected`, `data.egress_denied`, and `telemetry.channel_denied`.

The examples are synthetic and local. They do not make external network calls, do not use real secrets, and do not describe operational steps for exfiltrating data.
