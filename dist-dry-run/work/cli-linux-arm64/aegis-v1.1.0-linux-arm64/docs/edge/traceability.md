# Edge Traceability

Phase 33 writes `evidence/traceability.json` and `evidence/traceability.md`.

The traceability matrix links:

- policy rule
- command request
- safety finding
- final decision
- audit event id
- report section

Denied commands should have at least one rule, finding, or event reference. Unsupported or skipped items are represented explicitly instead of being counted as passes.

Traceability is an engineering audit aid. It is not certification evidence by itself and does not approve real flight.
