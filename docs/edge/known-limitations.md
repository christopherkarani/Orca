# Edge Known Limitations

This page is customer-readable and intentionally conservative.

## Safety and regulatory limits

- No real-flight readiness.
- No certification.
- No BVLOS approval.
- No detect-and-avoid.
- No autopilot replacement.
- No regulatory approval, airworthiness approval, or operational authorization.
- No guarantee that every unsafe action is prevented in real-world aircraft operations.

## MAVLink and vehicle limits

- No guarantee of all MAVLink commands covered.
- Unsupported MAVLink messages are classified as unsupported or unknown and must not be reported as safe.
- Unsupported vehicle modes are denied or reported as unsupported.
- MAVLink2 signing can be detected, but signing-key management and cryptographic verification are not implemented.
- Mission coverage is limited to the checked-in deterministic fake/SITL fixtures and supported command mappings.

## Geofence, coordinate, and altitude limits

- Supported geofence shapes: circular geofence policies.
- Unsupported geofence shapes: polygon geofences and dialect-specific fence messages.
- Coordinate-frame limitations: WGS84 and local-frame metadata must be explicit; unsupported local NED/ENU/body/home conversions fail clearly.
- Altitude-reference limitations: altitude references must match policy; unsupported conversions fail clearly.

## Environment limits

- PX4 SITL limitations: opt-in local simulation only; not real flight and not hardware validation.
- ArduPilot SITL limitations: opt-in local simulation only; not real flight and not hardware validation.
- Fake-adapter limitations: deterministic local fixture behavior only; not PX4 SITL, ArduPilot SITL, bench, hardware, or real-flight evidence.
- Bench-preparation limitations: no-actuation checks only; no flight instructions and no hardware approval.
- Hardware limitations: no real serial, radio, actuator, sensor, or aircraft endpoint is opened by default.

## Data, health, approval, and emergency limits

- Data guard limitations: local classification/redaction/egress decisions only; no hosted telemetry and no guarantee for customer-specific data formats without integration review.
- Runtime health limitations: local heartbeat/freshness/watchdog evidence only; no external monitoring service and no autopilot-failsafe replacement.
- Operator approval limitations: approval is local, scoped, expiring, and auditable; approval cannot make unsafe commands safe by default.
- Emergency behavior limitations: emergency fallback recommendations remain policy-controlled and do not override failsafes, geofence, raw actuator denial, or operator authority.

## Customer integration limits

- Customer-specific integration limitations depend on the customer's autopilot, MAVLink dialect, simulator, command surface, safety constraints, deployment environment, and data-handling requirements.
- Customer pilot materials are templates requiring customer, legal, safety, and commercial review before external use.
