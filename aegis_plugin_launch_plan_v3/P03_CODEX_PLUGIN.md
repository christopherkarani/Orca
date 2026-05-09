# P03 — Codex Plugin

## Objective

Build the Aegis Codex plugin package.

At the end of this phase, Codex users should be able to install or load the Aegis plugin locally, run Aegis skills, and have Codex lifecycle hooks call the Aegis CLI.

---

## Effort

**Recommended effort:** Medium-High

Use High if hooks actively block tool use.

---

## Scope

Implement:

- Codex plugin directory
- `.codex-plugin/plugin.json`
- skills
- hooks config
- README
- tests
- optional repo marketplace metadata if supported

---

## Non-goals

Do not add MCP config in this phase.

Do not add drone skills.

Do not add drone demos.

Do not duplicate Aegis policy logic.

Do not add SaaS, telemetry, or monetization.

---

## Directory

```text
integrations/codex-plugin/
  .codex-plugin/
    plugin.json
  skills/
    aegis-doctor/
      SKILL.md
    aegis-init/
      SKILL.md
    aegis-protect/
      SKILL.md
    aegis-redteam/
      SKILL.md
    aegis-replay/
      SKILL.md
  hooks/
    hooks.json
  README.md
```

---

## Skills

Create skills:

- `aegis-doctor`
- `aegis-init`
- `aegis-protect`
- `aegis-redteam`
- `aegis-replay`

No drone skill.

No MCP skill unless explicitly added later.

---

## Hooks

Codex hooks should call:

```bash
aegis hook codex <Event>
```

Events:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `Stop`

Do not duplicate policy logic.

---

## Security Requirements

- No secrets in plugin files.
- Hook output host-valid.
- Human logs to stderr.
- Aegis CLI remains source of truth.
- Plugin docs say `aegis run` is stronger than hooks alone.
- No drone exposure.
- No telemetry.

---

## Tests

Add tests for:

- manifest exists
- skills exist
- hooks call `aegis hook codex`
- no secrets in plugin files
- fake Codex hook payloads work
- plugin README includes limitations
- plugin files do not mention drone features except as an out-of-scope/non-regression note if necessary

---

## Acceptance Criteria

- Codex plugin directory exists.
- Manifest validates or passes schema-lite tests.
- Skills exist.
- Hooks call Aegis.
- No secrets leak.
- No drone plugin features exist.
- Local install docs exist.

---

## Codex Execution Prompt

```text
Implement P03: Codex Plugin.

Build the Codex plugin package under integrations/codex-plugin. Use .codex-plugin/plugin.json, root-level skills, hooks/hooks.json, README, and tests. Hooks must call `aegis hook codex`.

Do not add MCP config.
Do not add drone skills or drone demos.
Do not duplicate policy logic.

Run:
- zig build
- zig build test
- plugin structure tests
- fake Codex hook tests

Recommended effort: Medium-High.
```
