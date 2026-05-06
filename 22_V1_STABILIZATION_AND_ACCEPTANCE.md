# Phase 22 — v1.0 Stabilization and Acceptance

## Objective

Finalize Aegis v1.0.

At the end of this phase, Aegis should be ready for a v1.0 open-source release: stable CLI, stable policy schema, stable event schema, passing tests, working docs, release artifacts, and clear limitations.

---

## Scope

Implement:

- Final regression pass.
- Policy schema lock.
- Event schema lock.
- CLI UX polish.
- Performance checks.
- Cross-platform build verification.
- Red-team pass.
- Security docs verification.
- Release checklist completion.
- v1.0 changelog.
- Known limitations.
- Migration guidance from pre-1.0 if needed.

---

## Non-goals

Do not add major new features in this phase.

Do not start monetization work.

Do not introduce schema-breaking changes unless absolutely necessary.

---

## v1.0 Acceptance Checklist

### Build and Test

- [ ] `zig build` passes.
- [ ] `zig build test` passes.
- [ ] Linux build passes.
- [ ] macOS build passes.
- [ ] Windows build passes.
- [ ] Red-team CI passes.
- [ ] Example policies validate.
- [ ] Release artifacts build.

### CLI

- [ ] `aegis --help`
- [ ] `aegis version`
- [ ] `aegis version --json`
- [ ] `aegis init`
- [ ] `aegis init --preset generic-agent`
- [ ] `aegis doctor`
- [ ] `aegis run -- echo hello`
- [ ] `aegis replay --session last`
- [ ] `aegis policy check`
- [ ] `aegis policy explain`
- [ ] `aegis diff`
- [ ] `aegis apply`
- [ ] `aegis discard`
- [ ] `aegis mcp inspect`
- [ ] `aegis mcp proxy`
- [ ] `aegis redteam`

### Protection

- [ ] Env secrets stripped by default in strict mode.
- [ ] Fake secrets redacted from logs.
- [ ] `.env` read fixture blocked or detected according to backend capability.
- [ ] SSH key fixture blocked or detected according to backend capability.
- [ ] Dangerous command fixtures blocked.
- [ ] MCP malicious metadata flagged.
- [ ] Denied MCP tool call blocked.
- [ ] Network exfil fixture blocked or flagged according to backend capability.
- [ ] Staged writes can be reviewed before apply.

### Audit

- [ ] JSONL events are valid.
- [ ] Hash chain verifies.
- [ ] Tampering is detected.
- [ ] Replay output is readable.
- [ ] Session summaries are written.
- [ ] Redaction occurs before persistent logging.

### Docs

- [ ] README works.
- [ ] Quickstart works.
- [ ] Threat model is honest.
- [ ] Platform limitations are clear.
- [ ] Policy docs match schema.
- [ ] MCP docs match behavior.
- [ ] Install docs match release artifacts.
- [ ] Security disclosure process is clear.

### Release

- [ ] Changelog created.
- [ ] Version set to `1.0.0`.
- [ ] Checksums generated.
- [ ] SBOM generated or documented.
- [ ] Signing step complete or documented.
- [ ] GitHub release notes drafted.
- [ ] Package metadata updated.

---

## Performance Targets

Initial v1.0 targets:

- CLI startup under 100ms on typical developer machine where feasible.
- Policy loading under 50ms for normal policies.
- Audit event append under 5ms per event where feasible.
- MCP proxy overhead low enough to be unnoticeable for normal tool calls.
- Red-team suite completes quickly enough for CI.

These are targets, not hard blockers unless performance is obviously poor.

---

## Schema Lock

Create:

```text
schemas/policy-v1.json
schemas/event-v1.json
schemas/mcp-manifest-v1.json
```

Document:

- fields
- defaults
- compatibility promise
- future extension rules

After v1.0, breaking changes require a migration path.

---

## Final Manual Test Script

Create:

```text
scripts/v1-smoke-test.sh
scripts/v1-smoke-test.ps1
```

The script should run a representative subset:

```bash
aegis version
aegis doctor
aegis init --preset generic-agent --force
aegis policy check .aegis/policy.yaml
aegis run -- echo hello
aegis replay --session last --verify
aegis redteam --ci
```

---

## Acceptance Criteria

- All v1.0 acceptance checklist items are complete or explicitly documented as unsupported.
- All tests pass.
- Red-team suite passes.
- Docs match behavior.
- Release artifacts can be generated.
- Security limitations are documented.
- No major placeholder commands remain.
- The project is ready to tag `v1.0.0`.

---

## Codex Execution Prompt

```text
Implement Phase 22: v1.0 Stabilization and Acceptance.

Do not add major features. Stabilize the CLI, schemas, docs, tests, red-team suite, release artifacts, and smoke tests. Lock policy/event/manifest schemas, fix bugs, polish UX, and complete the v1.0 acceptance checklist.

Run:
- zig build
- zig build test
- aegis redteam --ci
- scripts/v1-smoke-test.sh if available
- cross-platform build checks where available

Provide a final v1.0 readiness report with completed checklist, known limitations, and release notes.
```

---

## Final Handoff

At the end of this phase, the repository should be ready for public v1.0 release.

Future post-v1.0 work can include monetization, SaaS dashboard, central policy management, enterprise audit retention, managed MCP gateway, SSO/SCIM/RBAC, hosted telemetry, and commercial support.


---

## Review Addendum — Final Evidence Gate

Before v1.0, produce a final evidence bundle:

- red-team report;
- smoke-test output;
- platform capability matrix;
- policy schema file;
- event schema file;
- MCP manifest schema file;
- checksums;
- known limitations;
- changelog;
- release notes.

If any production-readiness gate is not satisfied, v1.0 should not be tagged. Use a release candidate instead.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
