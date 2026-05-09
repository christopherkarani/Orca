# Edge Sensitive Data Redaction

The data guard redacts and minimizes sensitive payloads before audit, replay, report, and CLI output persistence.

Aegis Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

Redaction covers:

- Credentials, API-key-shaped values, bearer tokens, authorization fields, passwords, and fake secret markers.
- Secret-like URL query parameters.
- Operator/customer identifiers where policy requires minimization.
- Exact geolocation when policy requires coarse geolocation.
- Mission plans when policy denies or limits mission-data persistence.
- Raw image/video/audio/binary payloads by default.

Persistence rules:

- Secrets must not be written to persistent logs.
- Redaction happens before audit/report output.
- Query strings are bounded and redacted.
- Raw video frames, raw image frames, and raw unbounded binary payloads are not persisted by default.
- If safe redaction is not possible, strict/CI/red-team evaluation denies egress.

Synthetic fake secrets in `examples/edge/data-guard/payloads/fake-secret-payload.json` are only test fixtures. They are still treated as sensitive and must not appear in `events.jsonl`, replay output, safety-case reports, or red-team output.
