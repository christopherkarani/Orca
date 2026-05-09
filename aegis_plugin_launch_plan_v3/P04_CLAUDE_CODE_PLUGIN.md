# P04 — Claude Code Plugin

## Objective

Build the Aegis Claude Code plugin package.

At the end of this phase, Claude Code users should be able to install the Aegis plugin locally or through a marketplace catalog, run Aegis skills, and have Claude Code hooks call the Aegis CLI.

---

## Effort

**Recommended effort:** High

Claude Code hooks can return decisions, so output correctness matters.

---

## Scope

Implement:

- Claude Code plugin directory
- `.claude-plugin/plugin.json`
- skills
- hooks config
- marketplace file
- README
- tests

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
integrations/claude-code-plugin/
  .claude-plugin/
    plugin.json
  skills/
    doctor/
      SKILL.md
    init/
      SKILL.md
    protect/
      SKILL.md
    redteam/
      SKILL.md
    replay/
      SKILL.md
  hooks/
    hooks.json
  README.md
```

Marketplace:

```text
integrations/claude-marketplace/
  .claude-plugin/
    marketplace.json
  README.md
```

---

## Skills

User-facing skills should be documented as:

```text
/aegis:doctor
/aegis:init
/aegis:protect
/aegis:redteam
/aegis:replay
```

No drone skill.

No MCP skill unless explicitly added later.

---

## Hooks

Claude hooks should call:

```bash
aegis hook claude <Event>
```

Events:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `SessionEnd`

Use matchers for:

- shell tools
- file write/edit tools
- prompt submissions
- generic risky tools

---

## Security Requirements

- No secrets in plugin files.
- Hook output valid for Claude Code.
- Debug logs to stderr.
- Raw tool output not persisted by default.
- Aegis CLI remains source of truth.
- `aegis run` described as strongest local runtime protection.
- No drone exposure.
- No telemetry.

---

## Tests

Add tests for:

- manifest exists
- skills exist
- hooks call `aegis hook claude`
- marketplace file exists and validates schema-lite
- fake Claude hook payloads work
- fake secret prompt is redacted/blocked/warned
- dangerous command is denied or warned according to policy
- no secrets in plugin artifacts
- README includes limitations
- plugin files do not mention drone features except as an out-of-scope/non-regression note if necessary

---

## Acceptance Criteria

- Claude plugin directory exists.
- Manifest validates or passes schema-lite tests.
- Skills exist.
- Hooks call Aegis.
- Marketplace file exists.
- No secrets leak.
- No drone plugin features exist.
- Local and marketplace install docs exist.

---

## Codex Execution Prompt

```text
Implement P04: Claude Code Plugin.

Build integrations/claude-code-plugin and integrations/claude-marketplace. Use .claude-plugin/plugin.json, root-level skills, hooks/hooks.json, README, marketplace catalog, and tests. Hooks must call `aegis hook claude`.

Do not add MCP config.
Do not add drone skills or drone demos.
Do not duplicate policy logic.

Run:
- zig build
- zig build test
- plugin structure tests
- fake Claude hook tests
- marketplace schema-lite tests

Recommended effort: High.
```
