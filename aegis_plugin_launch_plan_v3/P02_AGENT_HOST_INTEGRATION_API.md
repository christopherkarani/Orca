# P02 — Agent Host Integration API

## Objective

Add the stable decision and hook API used by Codex and Claude Code plugins.

At the end of this phase, host plugins should be able to call Aegis through JSON-based commands for decisions, hooks, redaction-safe responses, and audit-aware behavior.

---

## Effort

**Recommended effort:** High

This API is the boundary between agent hosts and Aegis.

---

## Scope

Implement:

- `aegis decide`
- `aegis hook`
- host input normalization
- host output adapters
- hook request/response schemas
- Codex hook adapter
- Claude Code hook adapter
- tests with fake host payloads

---

## Non-goals

Do not build host plugin directories yet.

Do not build MCP server behavior.

Do not add drone decision types.

Do not duplicate the policy engine.

Do not make host hooks more powerful than the host supports.

Do not add SaaS, telemetry, or monetization.

---

## CLI Surface

### `aegis decide`

```bash
aegis decide command --json <payload>
aegis decide file --json <payload>
aegis decide prompt --json <payload>
aegis decide tool --json <payload>
```

Also support stdin:

```bash
cat payload.json | aegis decide command --stdin
```

### `aegis hook`

```bash
aegis hook codex SessionStart
aegis hook codex UserPromptSubmit
aegis hook codex PreToolUse
aegis hook codex PermissionRequest
aegis hook codex PostToolUse
aegis hook codex Stop

aegis hook claude SessionStart
aegis hook claude UserPromptSubmit
aegis hook claude PreToolUse
aegis hook claude PermissionRequest
aegis hook claude PostToolUse
aegis hook claude SessionEnd
```

Hook command behavior:

1. Read JSON from stdin.
2. Bound input size.
3. Normalize host payload.
4. Redact sensitive data.
5. Evaluate decision using existing Aegis policy/risk logic.
6. Emit host-valid response to stdout.
7. Emit human/debug logs only to stderr.
8. Persist audit events only after redaction.

---

## Decision Kinds

Support these decision kinds:

### `command`

For shell or command-like tool calls.

### `file`

For file write/edit/read tool calls.

### `prompt`

For user prompt submission checks such as pasted secrets.

### `tool`

Generic host tool call decision for non-command/non-file host tools.

If future MCP-specific decisions are needed, they can be added later. Do not add MCP as a dependency now.

---

## Schemas

Create:

```text
integrations/common/schemas/hook-request-v1.json
integrations/common/schemas/hook-response-v1.json
integrations/common/schemas/host-capabilities-v1.json
```

Decision output should include:

```json
{
  "version": 1,
  "decision": "block",
  "risk": "critical",
  "category": "command",
  "reason": "dangerous command pattern",
  "rule": "commands.deny[1]",
  "message": "Blocked by Aegis policy.",
  "redactions": []
}
```

Decision enum:

```text
allow
block
warn
ask
context_only
error
```

Risk enum:

```text
low
medium
high
critical
unknown
```

---

## Host Adapter Rules

### Codex

Codex hooks are useful guardrails, but host behavior can be limited. The adapter must not claim total enforcement if Codex treats a hook as advisory.

### Claude Code

Claude Code hooks can return decisions. The adapter should emit valid Claude Code hook outputs for the events it handles.

---

## Separate Workstream Guardrail

If the repo contains drone work or other safety-sensitive modules:

- do not modify those modules in P02
- do not add drone-specific decisions
- do not expose drone commands through hooks
- do not include drone-control instructions
- ensure existing tests still pass

---

## Security Requirements

- Raw secrets must never be persisted.
- Hook stdout must be host-valid.
- Debug output goes to stderr.
- CI mode never prompts.
- Invalid host JSON fails safely.
- Oversized host JSON fails safely.
- Host limitations are reported honestly.
- No real hardware or external network dependencies in tests.

---

## Tests

Add tests for:

- safe command decision
- dangerous command decision
- file write decision
- protected path decision if existing policy supports it
- prompt with fake secret
- generic host tool decision
- Codex fake `PreToolUse`
- Codex fake `UserPromptSubmit`
- Claude fake `PreToolUse`
- Claude fake `UserPromptSubmit`
- invalid JSON
- oversized JSON
- secret redaction
- stdout/stderr separation
- CI ask-to-deny

---

## Acceptance Criteria

- `aegis decide` works for command, file, prompt, and tool.
- `aegis hook codex PreToolUse` works with fake payload.
- `aegis hook claude PreToolUse` works with fake payload.
- No fake secrets leak.
- Existing tests still pass.
- Separate drone workstream is not modified or exposed.

---

## Codex Execution Prompt

```text
Implement P02: Agent Host Integration API.

Add `aegis decide` and `aegis hook` commands for Codex and Claude Code plugins. Include host JSON schemas, host adapters, redaction, and audit-safe behavior.

Do not build plugin packages yet.
Do not add MCP server behavior.
Do not add drone plugin behavior or drone decision types.
Do not modify drone modules except to preserve build/test compatibility.

Run:
- zig build
- zig build test
- fake Codex hook tests
- fake Claude hook tests
- existing drone tests if present

Recommended effort: High.
```
