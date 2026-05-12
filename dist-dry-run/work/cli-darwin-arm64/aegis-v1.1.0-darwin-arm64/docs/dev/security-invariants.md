# Security Invariants Summary

The authoritative security invariants remain in `../../SECURITY_INVARIANTS.md`.

Bootstrap code must not claim security enforcement. Future persistent logs must pass through redaction before writing, and future enforcement failures must fail closed in enforcing modes.
