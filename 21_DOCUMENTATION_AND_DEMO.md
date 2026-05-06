# Phase 21 — Documentation and Demo

## Objective

Create the launch-ready documentation, scary demo, examples, and compatibility matrix for Aegis v1.0.

At the end of this phase, a new developer should be able to understand Aegis, install it, run the demo, protect an agent session, inspect logs, and understand platform limitations.

---

## Scope

Implement:

- Launch README.
- Quickstart.
- Scary secret-exfiltration demo.
- Policy guide.
- MCP guide.
- Red-team guide.
- Platform guides.
- Agent recipes.
- CI guide.
- Troubleshooting guide.
- Compatibility matrix.
- Demo assets.
- Example policies.
- Example sessions.

---

## Non-goals

Do not exaggerate protection.

Do not include monetization language.

Do not require real secrets or real LLMs for the demo.

---

## README Structure

Suggested README:

```markdown
# Aegis

The open-source firewall for AI agents.

Run coding agents, MCP servers, and local automations without giving them your whole laptop.

## Demo

A malicious README tells an agent to steal `.env`.
Without Aegis: secret leaked.
With Aegis: blocked, logged, replayable.

## Install

...

## Quick Start

...

## What Aegis Protects

...

## What Aegis Does Not Promise

...

## MCP Firewall

...

## Red-team Your Setup

...

## Platform Support

...

## Why Zig?

...

## Contributing
```

---

## Scary Demo

Create a local deterministic demo:

```text
examples/leaky-agent-demo/
  README.md
  .env.example
  fake-agent/
  policy.yaml
  expected-output/
```

The demo should show:

1. A malicious README instructs an agent to read `.env`.
2. A fake agent attempts to read `.env`.
3. A fake agent attempts to exfiltrate via network-like URL or command.
4. Aegis blocks the secret read or network exfiltration.
5. Aegis writes audit logs.
6. `aegis replay --session last` shows exactly what happened.

Do not use a real secret. Use a fake value.

---

## Documentation Pages

Create/update:

```text
docs/quickstart.md
docs/install.md
docs/threat-model.md
docs/policy.md
docs/mcp.md
docs/redteam.md
docs/agent-recipes.md
docs/ci.md
docs/replay.md
docs/filesystem-staging.md
docs/network.md
docs/commands.md
docs/platform-linux.md
docs/platform-macos.md
docs/platform-windows.md
docs/troubleshooting.md
docs/contributing-fixtures.md
docs/release.md
```

---

## Compatibility Matrix

Include:

| Feature | Linux | macOS | Windows |
|---|---|---|---|
| Launch arbitrary command | yes | yes | yes |
| Env filtering | yes | yes | yes |
| Secret redaction | yes | yes | yes |
| Staged writes | yes | yes | yes |
| Command guard | yes | yes | yes |
| MCP stdio proxy | yes | yes | yes |
| Network guard | partial/full depending backend | limited/partial | limited/partial |
| Strong sandbox | available when supported | limited | limited |

Use actual current capability values from `aegis doctor`.

---

## Examples

Add examples for:

- Generic coding agent.
- MCP server proxy.
- GitHub Actions.
- Strict local policy.
- Trusted local policy.
- No-network session.
- Staged write review.
- Red-team run.

---

## Tests

Docs should have lightweight validation:

- Code blocks with commands are syntactically plausible.
- Example policies pass `aegis policy check`.
- Demo fixture passes `aegis redteam` or a demo-specific test.
- README links point to existing files.

---

## Acceptance Criteria

- README is launch-ready.
- Quickstart works from fresh clone.
- Demo works without real LLM or real secrets.
- Example policies validate.
- Platform limitations are clear.
- Docs do not overclaim security.
- `aegis redteam` output can be used in README.
- Install docs match release pipeline.

---

## Codex Execution Prompt

```text
Implement Phase 21: Documentation and Demo.

Create launch-ready README, quickstart, install docs, threat model, policy guide, MCP guide, red-team guide, platform docs, troubleshooting, examples, and a deterministic leaky-agent demo. Validate example policies and keep security claims honest.

Run:
- zig build
- zig build test
- aegis redteam --ci
- validate example policies
- run demo if feasible

Provide a handoff with files changed, tests run, known limitations, and doc notes.
```

---

## Handoff Notes for Next Phase

The final stabilization phase will lock schemas, polish performance, and produce v1.0 release readiness.


---

## Review Addendum — Docs Must Match Actual Capabilities

Documentation is part of the security boundary. Any README/demo claim must be backed by a test, fixture, or doctor capability.

The scary demo must use fake secrets, fake agents, and local-only exfiltration simulation. It must be runnable without a model provider account.


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
