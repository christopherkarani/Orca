# Edge Telemetry Policy

The data guard policy model separates telemetry channel decisions from endpoint and data-class decisions. A telemetry allow is not enough by itself: endpoint policy and data classification must also allow the egress request.

Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

Supported channel kinds include `mavlink_telemetry`, `command_control`, `mission_upload`, `mission_download`, `video_stream`, `image_snapshot`, `sensor_metadata`, `audit_report`, `safety_case_report`, `operator_approval`, `emergency_status`, `heartbeat`, `health_status`, and `unknown`.

Supported directions include `inbound`, `outbound`, `internal`, `external`, `vehicle_to_agent`, `agent_to_vehicle`, `edge_to_ground`, `edge_to_customer_endpoint`, and `unknown`.

Policy behavior:

- `deny` wins over `allow`.
- `ask` becomes `deny` in CI and noninteractive mode.
- `observe` mode emits audit and finding evidence without blocking where observe semantics apply.
- Unknown channels are not safe by default.
- Command/control links are distinguished from telemetry/data links and audited separately.
- Fake/SITL endpoints must remain labeled as fake or SITL, not real-flight or customer production endpoints.

The policy parser supports a `data_guard:` section with telemetry, endpoint, data-class, and egress settings. Use the examples in `examples/edge/data-guard/policies/` as the canonical local fixtures.
