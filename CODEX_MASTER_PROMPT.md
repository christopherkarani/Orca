# Codex Master Prompt Template

Use this prompt for every phase implementation.

Replace `{PHASE_FILE}` with the assigned phase markdown file. Paste the full contents of the listed context files into the Codex task or make sure Codex can read them from the repository.

---

```text
You are implementing Aegis, a Zig-based local runtime firewall for AI agents.

Read these files before making changes:

1. CODEX_AGENT_CONTEXT.md
2. CANONICAL_IMPLEMENTATION_DECISIONS.md
3. ARCHITECTURE_CONTRACTS.md
4. SECURITY_INVARIANTS.md
5. PRODUCTION_READINESS_GATES.md
6. PHASE_DEPENDENCY_MATRIX.md
7. {PHASE_FILE}

Implement only the assigned phase.

Rules:
- Preserve existing behavior unless the phase explicitly changes it.
- Use the canonical module layout and contracts.
- Do not add SaaS, telemetry, monetization, billing, cloud dashboard, or unrelated features.
- Do not claim enforcement that is not implemented and tested.
- Do not persist raw secrets anywhere.
- Route security decisions through the policy layer.
- Route persistent security events through the audit/redaction path.
- Add tests for all new behavior.
- Keep CI mode non-interactive.
- Document limitations honestly.

Run:
- zig build
- zig build test
- any phase-specific smoke tests

At the end, produce this handoff:

## Phase Handoff

### Completed
- ...

### Files Changed
- ...

### Tests Run
- ...

### Acceptance Criteria Status
- [x] ...
- [ ] ...

### Known Limitations
- ...

### Security Notes
- ...

### Dependency Notes
- New dependency: none
- Or document name/version/license/reason/security surface

### Next Phase Notes
- ...
```

---

## Reviewer Checklist After Codex Completes a Phase

Before merging a Codex-generated phase branch, verify:

- The phase did not implement out-of-scope product areas.
- `zig build` and `zig build test` pass.
- New behavior has tests.
- Security-relevant behavior has both allow and deny tests where applicable.
- No raw synthetic secret appears in logs, snapshots, or fixtures.
- Capability reporting is honest.
- Shared contracts were updated if APIs changed.
- Handoff notes are complete.
```
