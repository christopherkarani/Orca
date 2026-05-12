# Audit Health

Audit health checks detect unavailable writers, append failures, excessive append latency, and hash-chain verification failure. Strict and CI modes fail closed when audit persistence is required but broken.

If an audit failure prevents event writing, the CLI reports the failure and denies unsafe command forwarding. Fake secrets are redacted before persistence; raw secrets must not be written to events, replay, red-team reports, or safety-case reports.

Audit health is not real-flight readiness, not an autopilot replacement, and not regulatory certification.
