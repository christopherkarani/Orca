# Schemas

Versioned v1 JSON Schemas:

- `policy-v1.json`: Aegis policy file shape for `version: 1`.
- `event-v1.json`: audit `events.jsonl` record shape for `version: 1`.
- `mcp-manifest-v1.json`: stdio MCP manifest shape for `version: 1`.
- `edge-policy-placeholder-v1.json`: reserved placeholder for future Edge policy schemas.
- `edge-event-placeholder-v1.json`: reserved placeholder for future Edge audit-event schemas.
- `safety-report-placeholder-v1.json`: reserved placeholder for future safety-report schemas.

The runtime parsers reject unknown keys for these v1 formats. Future breaking schema changes require a new version and migration notes.

Edge and safety-report schemas are versioned Phase 26 domain/schema contracts only. They do not claim real drone enforcement, real-flight readiness, regulatory approval, MAVLink, PX4, or ArduPilot support.

- `edge-policy-v1.json`: policy shape for domain validation.
- `edge-event-v1.json`: future audit event name surface.
- `safety-report-v1.json`: future customer safety report shape and limitation fields.
