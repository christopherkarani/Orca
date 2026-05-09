# P07 — Plugin Launch and Post-launch

## Objective

Launch the Aegis plugin system publicly and prepare for fast post-launch patching.

---

## Effort

**Recommended effort:** Medium

Use High only if security or compatibility issues are found.

---

## Scope

Implement or prepare:

- plugin release notes
- launch announcement
- README updates
- plugin demo
- issue templates
- compatibility tracking
- post-launch triage labels
- first patch checklist

---

## Non-goals

Do not add product features.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not add monetization.

Do not overclaim plugin enforcement.

---

## Release Notes

Create:

```text
PLUGIN_RELEASE_NOTES.md
```

Sections:

- Aegis CLI plugin surface
- Codex plugin
- Claude Code plugin
- install
- verify
- demo
- known limitations
- security model
- vulnerability reports

Required sentence:

```text
The strongest protection remains running the agent through `aegis run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.
```

Also include:

```text
These plugins do not add MCP server functionality or drone-specific plugin features.
```

---

## Demo

Create:

```text
examples/plugin-demo/
  README.md
  codex-demo.md
  claude-demo.md
  fake-hook-payloads/
```

No real LLM is required for deterministic demos.

No drone demos.

No external network dependency.

---

## Issue Templates

Create/update:

```text
.github/ISSUE_TEMPLATE/codex_plugin_bug.md
.github/ISSUE_TEMPLATE/claude_plugin_bug.md
.github/ISSUE_TEMPLATE/aegis_cli_plugin_bug.md
.github/ISSUE_TEMPLATE/plugin_security_bug.md
.github/ISSUE_TEMPLATE/plugin_compatibility.md
```

---

## Triage Labels

Suggested labels:

```text
plugin:codex
plugin:claude
plugin:cli
plugin:hooks
plugin:install
plugin:marketplace
plugin:security
plugin:compatibility
plugin:docs
```

---

## Launch Checklist

- GitHub release includes plugin artifacts.
- Install docs work.
- Plugin doctor works.
- Codex plugin local install tested or documented.
- Claude plugin local/marketplace install tested or documented.
- Secret scan passes.
- Docs do not overclaim.
- Known limitations are clear.

---

## Acceptance Criteria

- Release notes exist.
- Launch announcement exists.
- Demo docs exist.
- Issue templates exist.
- Triage labels list exists.
- GitHub release checklist exists.
- Plugins are ready to publish.

---

## Codex Execution Prompt

```text
Implement P07: Plugin Launch and Post-launch.

Prepare plugin release notes, launch docs, README links, plugin demos, issue templates, triage labels, and first patch checklist. Do not add new product features.

Do not add MCP behavior.
Do not add drone plugin behavior.

Run:
- zig build
- zig build test
- plugin tests
- secret scan
- docs link validation if available

Recommended effort: Medium.
```
