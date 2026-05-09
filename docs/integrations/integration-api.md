# Integration API

> Scope: P01, local integration contract for `aegis decide` and `aegis hook`
> Version: 1.0.0

## Overview

Aegis exposes two local integration commands for agent hosts and wrappers:

- `aegis decide`, a direct policy evaluation API
- `aegis hook`, a host hook adapter for Codex and Claude Code events

Both commands are local only. They read `.aegis/policy.yaml`, apply policy, and return structured JSON. They do not provide sandboxing by themselves. The strongest protection remains `aegis run -- <command>`.

## `aegis decide`

`aegis decide` evaluates a single request against policy and returns a JSON decision.

### Usage

```sh
aegis decide command --json '{"command":"<cmd>"}'
aegis decide file    --json '{"path":"<p>","operation":"read|write"}'
aegis decide prompt  --json '{"text":"<text>"}'
aegis decide tool    --json '{"name":"<name>"}'

aegis decide <kind> --stdin
aegis decide <kind> --json <payload> [--ci]
aegis decide <kind> --stdin [--ci]
```

Kinds:

- `command`
- `file`
- `prompt`
- `tool`

Options:

- `--json`, inline JSON payload
- `--stdin`, read JSON from stdin
- `--ci`, treat `ask` as deny

### Evaluation rules

- The command loads `.aegis/policy.yaml`.
- `command` checks against policy command allow and deny rules.
- `file` checks file access rules using the supplied `operation`.
- `prompt` checks text for policy relevant content and redaction triggers.
- `tool` checks tool names against policy tool rules.
- If the request is malformed, the command returns a usage or general error.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Allow or success |
| `1` | General error |
| `2` | Usage error |
| `3` | Policy denied |
| `4` | Ask, in non CI mode |
| `5` | Redact or warn |

### Examples

Allow a command:

```sh
aegis decide command --json '{"command":"git status"}'
```

Check a file write:

```sh
aegis decide file --json '{"path":"src/main.zig","operation":"write"}'
```

Check a prompt:

```sh
aegis decide prompt --json '{"text":"Do not include secrets in the response."}'
```

Check a tool name from stdin:

```sh
printf '{"name":"edit"}' | aegis decide tool --stdin
```

CI mode example:

```sh
aegis decide command --json '{"command":"git push --force"}' --ci
```

In CI mode, any `ask` result becomes a deny path.

## `aegis hook`

`aegis hook` adapts host events to Aegis policy decisions.

### Usage

```sh
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

### Hosts

- `codex`
- `claude`

### Events

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `Stop`
- `SessionEnd`

### Request schema

Hooks always read a JSON request from stdin.

```json
{
  "version": 1,
  "host": "codex|claude",
  "event": "SessionStart|UserPromptSubmit|PreToolUse|PermissionRequest|PostToolUse|Stop|SessionEnd",
  "payload": {},
  "session_id": "optional",
  "timestamp": "optional ISO 8601"
}
```

### Request handling

- `SessionStart`, `Stop`, `SessionEnd`, `PostToolUse` always return allow style responses.
- `UserPromptSubmit` scans prompt text for secrets and redacts if needed.
- `PreToolUse` and `PermissionRequest` route to command, file, or tool evaluation.
- File tools are matched case insensitively.
- Payloads larger than 256 KiB are rejected.

#### Decision routing

If the payload has `command`, Aegis evaluates it as a command.

If the tool name matches a file tool and the payload has `path`, Aegis evaluates it as a file write:

- `edit`
- `write`
- `file_write`
- `file_edit`
- `apply`
- `create_file`
- `write_file`

Otherwise, Aegis treats the event as an MCP or tool request. In strict mode, that defaults to deny when policy does not allow it.

### Response schema

Responses are written to stdout.

```json
{
  "version": 1,
  "decision": "allow|block|warn|ask|context_only|error",
  "risk": "low|medium|high|critical|unknown",
  "category": "command|file|prompt|tool|network|mcp|unknown",
  "reason": "machine-readable reason",
  "rule": "matched rule id or null",
  "message": "human-readable message",
  "redactions": [{"field":"...","reason":"..."}],
  "host_limitations": ["Hook enforcement is additive; does not replace aegis run supervision."]
}
```

### Decision mapping

| Aegis decision | Hook response |
|---|---|
| `allow` | `allow` |
| `deny` | `block` |
| `ask` | `ask`, or `block` in CI |
| `observe` | `context_only` |
| `redact` | `warn` |
| `stage` | `ask`, or `block` in CI |
| `broker` | `error` |

### Examples

Session start:

```sh
printf '{"version":1,"host":"codex","event":"SessionStart","payload":{}}' | aegis hook codex SessionStart
```

Prompt submit with a secret:

```sh
printf '{"version":1,"host":"claude","event":"UserPromptSubmit","payload":{"text":"my token is abc123"}}' | aegis hook claude UserPromptSubmit
```

Tool request:

```sh
printf '{"version":1,"host":"codex","event":"PreToolUse","payload":{"name":"edit","path":"README.md"}}' | aegis hook codex PreToolUse
```

CI mode:

```sh
printf '{"version":1,"host":"claude","event":"PermissionRequest","payload":{"command":"git push --force"}}' | aegis hook claude PermissionRequest --ci
```

## JSON Schemas Reference

The schemas below are the integration contract reference. They are intentionally small and versioned.

### `hook-request-v1`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "hook-request-v1",
  "type": "object",
  "required": ["version", "host", "event", "payload"],
  "properties": {
    "version": {"const": 1},
    "host": {"enum": ["codex", "claude"]},
    "event": {
      "enum": [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PermissionRequest",
        "PostToolUse",
        "Stop",
        "SessionEnd"
      ]
    },
    "payload": {"type": "object"},
    "session_id": {"type": "string"},
    "timestamp": {"type": "string"}
  },
  "additionalProperties": true
}
```

### `hook-response-v1`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "hook-response-v1",
  "type": "object",
  "required": ["version", "decision", "risk", "category", "reason", "message", "redactions", "host_limitations"],
  "properties": {
    "version": {"const": 1},
    "decision": {"enum": ["allow", "block", "warn", "ask", "context_only", "error"]},
    "risk": {"enum": ["low", "medium", "high", "critical", "unknown"]},
    "category": {"enum": ["command", "file", "prompt", "tool", "network", "mcp", "unknown"]},
    "reason": {"type": "string"},
    "rule": {"type": ["string", "null"]},
    "message": {"type": "string"},
    "redactions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["field", "reason"],
        "properties": {
          "field": {"type": "string"},
          "reason": {"type": "string"}
        },
        "additionalProperties": true
      }
    },
    "host_limitations": {
      "type": "array",
      "items": {"type": "string"}
    }
  },
  "additionalProperties": true
}
```

### `host-capabilities-v1`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "host-capabilities-v1",
  "type": "object",
  "required": ["version", "host", "events", "supports_stdin", "supports_ci"],
  "properties": {
    "version": {"const": 1},
    "host": {"enum": ["codex", "claude"]},
    "events": {
      "type": "array",
      "items": {
        "enum": [
          "SessionStart",
          "UserPromptSubmit",
          "PreToolUse",
          "PermissionRequest",
          "PostToolUse",
          "Stop",
          "SessionEnd"
        ]
      }
    },
    "supports_stdin": {"type": "boolean"},
    "supports_ci": {"type": "boolean"},
    "max_payload_bytes": {"type": "integer"},
    "file_tools": {"type": "array", "items": {"type": "string"}}
  },
  "additionalProperties": true
}
```

## CI Mode

CI mode is fail closed for asks.

- In `aegis decide`, `ask` becomes a non interactive deny path.
- In `aegis hook`, `ask` becomes `block`.
- `warn` still returns warning output, but it does not become allow.
- CI mode does not add new policy rules. It only changes the fallback behavior for undecided actions.

## Error Handling

Common failures include:

- bad or missing JSON payloads
- invalid `kind`, `host`, or `event`
- unsupported payload shapes
- payloads over 256 KiB
- missing `.aegis/policy.yaml`
- policy parse failures
- internal evaluation errors

`aegis decide` uses exit codes for command line callers. `aegis hook` always writes a JSON response and should return an `error` decision when it can parse the request but cannot complete evaluation.

When possible, error responses should be explicit about the failed stage, but they should not print secrets or raw payloads.

## Limitations

- These commands are local policy adapters, not a sandbox.
- They only see the events and payloads the host provides.
- They cannot enforce actions the host never reports.
- File tool matching is based on known tool names and path presence.
- Network and MCP requests are only as visible as the host event stream makes them.
- Host hook enforcement is additive. It does not replace `aegis run` supervision.
- `observe`, `context_only`, and similar non blocking responses are informational. A host may still choose its own final behavior.
