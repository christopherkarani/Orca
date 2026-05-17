# Edge Data Classification

The data guard classifier assigns Edge payloads to data classes and sensitivity levels before egress evaluation.

Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

Data classes are:

- `public`
- `operational`
- `vehicle_state`
- `vehicle_identifier`
- `mission_plan`
- `geolocation`
- `operator_identifier`
- `customer_identifier`
- `sensor_metadata`
- `image_frame`
- `video_stream`
- `audio_stream`
- `map_data`
- `safety_finding`
- `audit_metadata`
- `credential`
- `secret`
- `unknown`

Sensitivity levels are `low`, `medium`, `high`, `critical`, and `unknown`.

Classification rules:

- Credentials and secrets are critical.
- Exact geolocation, mission plans, operator/customer identifiers, image frames, and video streams are high by default.
- Unknown payloads are not treated as safe.
- Sensitive payloads must be redacted, minimized, denied, or explicitly allowed by policy before external egress.
- Safety-case reports can be allowed to an explicit simulated customer endpoint, but the report must not leak raw payloads, exact secrets, raw video/image frames, or full mission details unless policy permits them.
