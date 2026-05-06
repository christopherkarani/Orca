# Phase 01 — Codex Execution Protocol

## Objective

Define the operating protocol for Codex coding agents that implement Aegis phases.

This file is not a product feature. It is the implementation contract. Every later phase should be executed according to this protocol.

---

## Core Principle

Codex should implement one phase at a time, leave the repository in a working state, run tests, and produce a concise handoff note.

Aegis is security-sensitive. Prefer simple, explicit, tested code over clever abstractions.

---

## Required Agent Behavior

When given a phase file, Codex must:

1. Read the phase objective.
2. Inspect the repository before editing.
3. Identify existing modules that should be extended rather than replaced.
4. Implement the smallest complete version that satisfies acceptance criteria.
5. Add or update tests.
6. Run relevant tests.
7. Update docs or handoff notes if the phase asks for them.
8. Report:
   - files changed
   - tests run
   - known limitations
   - acceptance criteria status

Codex must not:

- Delete unrelated code.
- Rewrite large modules without need.
- Add unnecessary dependencies.
- Implement monetization/SaaS features.
- Claim security guarantees that are not enforced.
- Hide failing tests.
- Leave placeholders that pretend to be complete.
- Expand scope beyond the current phase unless needed to satisfy acceptance criteria.

---

## Repository Hygiene

Each phase should be implemented on a branch:

```bash
git checkout -b phase-XX-short-name
```

Every phase should pass:

```bash
zig build
zig build test
```

If platform-specific tests cannot run locally, Codex should add them behind target checks and document the limitation.

---

## Coding Style

Use Zig idioms:

- Explicit errors.
- Explicit allocation.
- Small modules.
- Clear ownership.
- No hidden global mutable state unless justified.
- Avoid unbounded reads from untrusted inputs.
- Prefer deterministic behavior.
- Prefer plain data structures over framework-heavy designs.

Security-sensitive code should be boring.

---

## Error Handling Rules

Every security-relevant function should return explicit errors. Example:

```zig
pub const AegisError = error{
    PolicyParseFailed,
    PolicyValidationFailed,
    AuditLogUnavailable,
    SandboxUnavailable,
    PermissionDenied,
    UserDenied,
    UnsupportedPlatformFeature,
    InputTooLarge,
    InvalidUtf8,
};
```

Do not collapse security errors into generic `error.Unknown`.

---

## Logging Rules

Aegis has multiple output channels:

1. User-facing terminal output.
2. Persistent audit events.
3. Debug logs.
4. Test output.

Never log raw secret values. All persistent logs must pass through redaction before writing.

---

## Testing Requirements

Every phase should add tests matching the feature being implemented.

Preferred test types:

- Unit tests for pure functions.
- Golden tests for CLI output.
- Integration tests for process/session behavior.
- Fixture tests for red-team behavior.
- Platform-gated tests for OS-specific backends.

Tests should be deterministic and not require external network access unless specifically marked and skipped by default.

---

## Security Review Checklist Per Phase

Codex should answer these questions at handoff:

- Does this phase touch untrusted input?
- Does this phase touch file paths?
- Does this phase execute commands?
- Does this phase read or write secrets?
- Does this phase persist logs?
- Does this phase parse network/MCP data?
- What are the likely bypasses?
- What tests cover those bypasses?

---

## Handoff Format

At the end of each phase, Codex should produce:

```markdown
## Phase Handoff

### Completed
- ...

### Tests Run
- `zig build test`
- ...

### Known Limitations
- ...

### Security Notes
- ...

### Next Phase Notes
- ...
```

This handoff can be included in the PR description or committed to `docs/dev/phase-handoffs/phase-XX.md`.

---

## Global Non-goals for All Codex Phases

Do not build:

- A SaaS product.
- A cloud dashboard.
- Enterprise billing.
- License enforcement.
- Telemetry by default.
- A new AI agent.
- A model provider integration that requires secrets.
- A GUI unless a later phase explicitly asks for it.

---

## Codex Prompt Template

Use this template when assigning a phase:

```text
You are implementing Aegis, a Zig-based local runtime firewall for AI agents.

Read this phase file fully. Implement only this phase. Preserve existing behavior. Add tests. Run `zig build` and `zig build test`. Do not add SaaS, telemetry, monetization, or unrelated features.

At the end, provide a handoff with:
- files changed
- tests run
- known limitations
- acceptance criteria status
- security notes

Phase file:
[paste phase markdown here]
```


## Reviewed Production Protocol Addendum

Every phase implementation must also follow:

- `CODEX_AGENT_CONTEXT.md`
- `CANONICAL_IMPLEMENTATION_DECISIONS.md`
- `ARCHITECTURE_CONTRACTS.md`
- `SECURITY_INVARIANTS.md`
- `PRODUCTION_READINESS_GATES.md`

A phase is incomplete if it introduces a new security-relevant behavior without:

1. policy decision path;
2. audit event path;
3. redaction path where data may contain secrets;
4. tests for allow and deny behavior;
5. capability/limitation documentation.

### Do Not Invent Incompatible APIs

Before creating a new type or module, check `CANONICAL_IMPLEMENTATION_DECISIONS.md` and `ARCHITECTURE_CONTRACTS.md`. If a phase must change a shared contract, update the contract document in the same change and call it out in the handoff.

### Production Honesty Rule

If Codex cannot implement a protection fully, it must implement one of these honest states:

- `active`: implemented and tested;
- `partial`: implemented for some cases, documented;
- `observe`: logs but does not enforce;
- `limited`: useful but bypassable wrapper/proxy-level protection;
- `unavailable`: not implemented on this platform.

Never label observe-only behavior as enforcement.
