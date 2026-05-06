# Phase 18 — Agent Presets and Integrations

## Objective

Make Aegis easy to adopt with common agent workflows, repository presets, MCP presets, and CI integrations.

At the end of this phase, users should be able to initialize practical policies for common coding-agent setups and run Aegis in local or CI environments with minimal manual configuration.

---

## Scope

Implement:

- Policy presets.
- Agent recipes.
- MCP server presets.
- GitHub Actions integration.
- Generic CI mode.
- Shell completions.
- `aegis init --preset`.
- `aegis doctor` integration checks.
- Documentation for each preset.

---

## Non-goals

Do not build SaaS policy sync.

Do not hardcode proprietary secrets or require specific model providers.

Avoid brittle assumptions about exact agent internals. Presets should be useful but easy to modify.

---

## Presets

Create policy presets for:

```text
policies/presets/
  generic-agent.yaml
  claude-code.yaml
  codex.yaml
  cursor-agent.yaml
  opencode.yaml
  cline-roo.yaml
  mcp-dev.yaml
  github-actions.yaml
  strict-local.yaml
  trusted-local.yaml
```

Names can change, but support generic categories if exact tool behavior is unknown.

---

## `aegis init --preset`

Examples:

```bash
aegis init --preset generic-agent
aegis init --preset codex
aegis init --preset mcp-dev
aegis init --preset github-actions
```

Behavior:

- Creates `.aegis/policy.yaml`.
- Writes preset-specific comments.
- Warns if preset is generic/experimental.
- Does not overwrite without `--force`.

---

## GitHub Actions

Create:

```text
.github/actions/aegis-run/action.yml
docs/ci/github-actions.md
```

Example usage:

```yaml
name: Agent Task

on:
  workflow_dispatch:

jobs:
  agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Aegis
        run: ./scripts/install-aegis.sh
      - name: Run agent safely
        run: aegis run --mode ci -- ./scripts/agent-task.sh
      - name: Upload Aegis audit logs
        uses: actions/upload-artifact@v4
        with:
          name: aegis-audit
          path: .aegis/sessions
```

---

## Shell Completions

Generate or provide completions for:

- bash
- zsh
- fish
- PowerShell

Command:

```bash
aegis completions bash
aegis completions zsh
aegis completions fish
aegis completions powershell
```

---

## Integration Doctor

`aegis doctor` should detect:

- Git repository.
- Existing `.aegis/policy.yaml`.
- Known agent binaries in PATH, if feasible.
- MCP manifests.
- CI environment.
- Shell type.
- Platform backend capabilities.

---

## Tests

Add tests for:

- Preset files validate.
- `aegis init --preset` writes expected policy.
- `--force` overwrite behavior.
- GitHub Actions sample has expected command.
- Completions command returns non-empty output.
- Doctor detects policy file in temp repo.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- All presets pass `aegis policy check`.
- `aegis init --preset generic-agent` works.
- `aegis init --preset github-actions` works.
- Shell completions are generated or installed.
- CI docs include a working example.
- Doctor gives useful setup recommendations.

---

## Codex Execution Prompt

```text
Implement Phase 18: Agent Presets and Integrations.

Add policy presets, `aegis init --preset`, GitHub Actions example, shell completions, integration doctor checks, and docs for local/CI agent workflows. Keep presets generic and editable.

Run:
- zig build
- zig build test
- aegis policy check for every preset
- manual smoke: aegis init --preset generic-agent

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Installer/release pipeline will package these presets and completions. Ensure they are included in release artifacts or embedded.


---

## Review Addendum — Presets Must Be Safe Defaults, Not Exact Claims

Agent presets should be conservative and editable. Avoid claiming exact compatibility with a proprietary agent unless verified by tests or docs. Generic presets are acceptable if clearly labeled.

Every preset must pass policy validation and include comments explaining risky permissions.


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
