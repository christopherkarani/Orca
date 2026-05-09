# P06 — Plugin Distribution and Marketplace

## Objective

Package and distribute the Aegis CLI plugin surface, Codex plugin, and Claude Code plugin.

At the end of this phase, users should be able to install or load the plugins from public instructions and release artifacts.

---

## Effort

**Recommended effort:** Medium

This phase is operational, but must preserve security.

---

## Scope

Implement:

- plugin release packaging
- plugin checksums
- Codex distribution instructions
- Claude marketplace catalog
- install/uninstall docs
- release workflow updates
- compatibility matrix
- plugin changelog

---

## Non-goals

Do not add SaaS.

Do not add telemetry.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not require official marketplace approval before users can install locally.

---

## Release Artifacts

Create:

```text
dist/plugins/aegis-codex-plugin-vX.Y.Z.zip
dist/plugins/aegis-claude-code-plugin-vX.Y.Z.zip
dist/plugins/aegis-plugin-checksums.txt
```

Artifacts must include:

- manifest
- skills
- hooks
- README
- no secrets
- no unnecessary build outputs

---

## Codex Distribution

Support:

- local plugin install instructions
- repo marketplace instructions if supported
- release artifact instructions
- official directory submission checklist if available

Do not claim official marketplace availability unless it exists.

---

## Claude Distribution

Support:

- local plugin install
- marketplace catalog file
- marketplace add/install instructions
- release artifact install
- official marketplace submission notes if desired

---

## Install Docs

Create/update:

```text
docs/integrations/aegis-cli-plugin.md
docs/integrations/codex.md
docs/integrations/claude-code.md
docs/integrations/plugin-troubleshooting.md
docs/integrations/plugin-security-model.md
docs/integrations/separate-workstream-guardrails.md
```

Each doc must include:

- prerequisites
- install
- verify with plugin doctor
- run redteam
- run replay
- uninstall
- limitations
- no telemetry statement
- note that plugins do not include MCP or drone support unless separately added later

---

## Release Workflow

Update release workflow to:

- package plugin zips
- generate checksums
- run plugin tests
- scan artifacts for secrets
- upload artifacts

---

## Acceptance Criteria

- Plugin packages generated.
- Checksums generated.
- Claude marketplace file exists.
- Codex install docs exist.
- Claude install docs exist.
- Aegis CLI plugin docs exist.
- No secrets in artifacts.
- Release workflow includes plugin artifacts.

---

## Codex Execution Prompt

```text
Implement P06: Plugin Distribution and Marketplace.

Package Codex and Claude plugins, generate checksums, add Claude marketplace catalog, write Codex/Claude/Aegis CLI plugin install docs, update release workflow, and include separate-workstream guardrail notes.

Do not add MCP behavior.
Do not add drone plugin behavior.

Run:
- zig build
- zig build test
- plugin package generation
- plugin checksum generation
- secret scan over dist/plugins

Recommended effort: Medium.
```
