# Codex Agent Context Pack

Paste this file with every individual phase prompt.

## Product

Aegis is a Zig-based, local-first runtime firewall for AI agents. It launches existing agent tools inside a policy-controlled session, strips secrets, blocks dangerous file access, stages writes, mediates shell commands, controls network egress, proxies MCP servers, records tamper-evident audit logs, and ships with red-team fixtures.

Primary promise:

> Run your AI coding agent without giving it your whole laptop.

Aegis is not a new AI agent, not a model provider, not a SaaS product, and not an enterprise dashboard in v1.0.

## v1.0 Definition

Aegis v1.0 is production-ready when it is:

- buildable on Linux, macOS, and Windows;
- honest about platform capability levels;
- safe-by-default for secrets and logs;
- tested with deterministic red-team fixtures;
- able to run real local agent commands;
- able to proxy stdio MCP servers;
- able to record and replay tamper-evident sessions;
- documented clearly enough for developers and security reviewers;
- released with checksums and repeatable build instructions.

Production-ready does **not** mean perfect kernel-level containment on every OS. It means the controls that are claimed are implemented, tested, and documented.

## Required Shared Documents

Before implementing any phase, read:

1. `00_PROJECT_INDEX.md`
2. `01_CODEX_EXECUTION_PROTOCOL.md`
3. `CANONICAL_IMPLEMENTATION_DECISIONS.md`
4. `ARCHITECTURE_CONTRACTS.md`
5. `SECURITY_INVARIANTS.md`
6. `PRODUCTION_READINESS_GATES.md`
7. the assigned phase file

Use `PHASE_DEPENDENCY_MATRIX.md` when a phase depends on earlier outputs. If any older phase text conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

## Non-negotiable Security Rules

- Never persist raw secrets to logs, snapshots, summaries, test output, or fixture reports.
- All persistent logging must pass through the redaction path.
- Invalid policy must fail closed except in explicit `observe` mode.
- CI mode must never wait for interactive approval.
- Any unsupported enforcement feature must be reported as `limited`, `observe`, or `unavailable`, not silently treated as active.
- Deny must win over allow unless an explicit and tested override mechanism exists.
- Never claim transparent enforcement unless the backend actually enforces it.
- No tests should require real credentials, real external services, or real LLM calls.

## Dependency Policy

Aegis is a security-sensitive systems tool. Dependencies are allowed only when they are clearly justified.

For every new dependency, Codex must document:

- name and version/source;
- license;
- why stdlib or local code is insufficient;
- whether it parses untrusted input;
- whether it is used in security-critical code;
- how it is tested.

Avoid dependencies for simple CLI parsing, globbing, hashing, redaction, and JSON if Zig stdlib is sufficient. YAML support may require a dependency or a deliberately small parser; whichever route is chosen must be documented.

## Standard Phase Completion Output

Every phase handoff must include:

```markdown
## Phase Handoff

### Completed
- ...

### Files Changed
- ...

### Tests Run
- `zig build`
- `zig build test`
- ...

### Acceptance Criteria Status
- [x] ...
- [ ] ...

### Known Limitations
- ...

### Security Notes
- ...

### Next Phase Notes
- ...
```

## Coding Style

- Prefer explicit, small modules.
- Keep policy, audit, redaction, sandbox, MCP, network, and CLI concerns separated.
- Use deterministic behavior for tests.
- Treat untrusted inputs as bounded: max length, max depth, max count.
- Prefer fail-closed behavior for security-sensitive failures.
- Keep user-facing error messages specific and actionable.

## No-placeholder Rule

Placeholders are allowed only if they are honest and cannot be mistaken for real enforcement. Example:

Good:

```text
network enforcement: unavailable on this platform; proxy-observe mode active
```

Bad:

```text
network enforcement: active
```

when only logging exists.
