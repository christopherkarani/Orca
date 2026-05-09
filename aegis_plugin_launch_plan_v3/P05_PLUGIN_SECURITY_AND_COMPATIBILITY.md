# P05 — Plugin Security and Compatibility

## Objective

Build a security and compatibility test suite for the Aegis plugin surface, Codex plugin, and Claude Code plugin.

This phase also verifies that separate workstreams such as drone work were not modified or exposed by the plugin implementation.

---

## Effort

**Recommended effort:** High

Plugins sit at the boundary between agent hosts and Aegis decisions, so bad output shapes or secret leakage can create high-impact failures.

---

## Scope

Implement:

- plugin fixture tests
- fake Codex payloads
- fake Claude payloads
- plugin artifact secret scans
- docs overclaim checks
- hook timeout/invalid input tests
- separate-workstream non-regression checks
- optional host validation tests

---

## Non-goals

Do not add new plugin features.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not add telemetry or SaaS.

---

## Fixtures

Create:

```text
tests/plugin-fixtures/
  codex/
  claude/
```

All secrets must be fake and synthetic.

---

## Required Tests

### Plugin Structure

- Codex manifest exists.
- Claude manifest exists.
- Skills exist.
- Hooks exist.
- Marketplace file valid if present.
- No MCP config is required.
- No drone skills exist.

### Hook Behavior

- safe shell command allowed
- dangerous shell command denied/warned
- fake secret prompt redacted/blocked/warned
- protected file write denied/warned
- invalid payload fails safely
- oversized payload fails safely
- stdout/stderr separation preserved
- CI mode never prompts

### Secret Safety

Scan:

- plugin files
- generated hook responses
- audit logs
- replay output
- docs
- marketplace files
- plugin packages

No fake secrets should appear.

### Docs Claims

Docs must not claim:

- perfect sandboxing
- universal transparent file enforcement
- universal transparent network enforcement
- protection for agents not launched through Aegis
- protection against root/admin/kernel compromise
- MCP plugin support unless added later
- drone plugin support

### Separate Workstream Non-regression

If drone work exists:

- plugin files should not expose drone commands
- plugin docs should not include drone demos
- plugin phases should not modify drone modules except safe docs/safepoint notes
- existing drone tests should pass or safe skip reasons should be documented

---

## Optional Local Host Tests

If Codex is installed:

- validate local plugin install if supported
- run plugin doctor skill if feasible

If Claude Code is installed:

- run plugin validation if available
- test local plugin install or marketplace add if feasible

Skip cleanly if host tools are not installed.

---

## Acceptance Criteria

- Plugin security tests pass.
- No secrets leak.
- Existing Aegis tests pass.
- Existing drone tests, if present, pass or unsupported reasons are documented.
- Docs are honest.
- Plugin artifacts are safe to package.

---

## Codex Execution Prompt

```text
Implement P05: Plugin Security and Compatibility.

Add plugin security fixtures, fake host payload tests, secret scans, docs overclaim checks, invalid/oversized input tests, and separate-workstream non-regression checks.

Do not add MCP behavior.
Do not add drone plugin behavior.

Run:
- zig build
- zig build test
- plugin fixture tests
- existing drone tests if present
- secret scan over plugin artifacts and docs

Recommended effort: High.
```
