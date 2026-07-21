# Zig coverage tooling decision

Tracked ADR for the **Zig security test depth** sweep
(`planning/100-percent-test-coverage-agent-plan.md`).  
**Only path** for mode A/B/D — do not also record under `orca-rs/`.

## Decision record

- mode: **D**
- decision_date: 2026-07-21
- human_ack: christopherkarani
- zig_version: 0.16.0
- commands_tried: |
    No kcov/gcov or llvm-profdata integration attempted in-tree for this sweep.
    Rationale: Zig 0.16 has no first-class cargo-llvm-cov equivalent checked into
    this repo; scripts/ has no zig-coverage helper; CI has zig build/test only.
    Mode D (behavior checklist + journeys) unblocks security-depth work without
    inventing line-% or a false zig-coverage job.
- wall_time_sample: n/a (mode D)
- sample_artifact: n/a
- ci_job_plan: none
- kill_reason: A/B not staffed for this sweep; default to checklist-only (D) so
  agents can close fail-closed / host-wire residual gaps without line-% claims.
- notes: |
    - Zig-S5 and "Zig 100% lines" are **forbidden** under mode D.
    - Reopen this file to switch to A or B after a real spike with measured % and
      optional path-filtered CI job (never continue-on-error; not required until H1).
    - Progress metrics: docs/testing/zig-security-checklist.toml and
      docs/testing/journey-matrix.md (sweep: zig rows only).

## Mode meanings (reference)

| Mode | Meaning | Zig-S5? |
|------|---------|---------|
| A | kcov/gcov (or equivalent) → falsifiable line % | After two consecutive CI % runs |
| B | llvm-profdata / source-based coverage | After two consecutive CI % runs |
| C | Custom tracers | Rejected for Zig-S5 |
| D | Behavior checklist only (this decision) | **No** |

## Related artifacts

| Artifact | Path |
|----------|------|
| Behavior checklist | `docs/testing/zig-security-checklist.toml` |
| Journey matrix | `docs/testing/journey-matrix.md` |
| Slice backlog | `docs/testing/zig-coverage-slice-backlog.md` |
| Agent plan | `planning/100-percent-test-coverage-agent-plan.md` |
