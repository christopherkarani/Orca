# Evidence Package

The Phase 38 proof package includes:

- Demo policy and scenario files.
- Safety report examples.
- Replay example.
- Traceability matrix example.
- Red-team scorecard example.
- Capability matrix.
- Known limitations.

Every artifact must include provenance, limitations, a non-certification disclaimer, and no raw secrets.

Generated local sessions are written under `.edge/sessions/<session-id>/` and can contain:

- `events.jsonl`
- `summary.json`
- `summary.md`
- `safety-report.json`
- `safety-report.md`
- `evidence/replay.md`
- `final-hash.txt`

These files are customer-evaluation evidence only.
