# Integration API

> Scope: P01, local integration contract for `orca decide` and `orca hook`
> Version: 1.0.0

## Overview

Orca exposes two local integration commands for agent hosts and wrappers:

- `orca decide`, a direct policy evaluation API
- `orca hook`, a host hook adapter for Codex and Claude Code events

Both commands are local only. They read `.orca/policy.yaml`, apply policy, and return structured JSON. They do not provide sandboxing by themselves. The strongest protection remains `orca run -- <command>`.

## `orca decide`

`orca decide` evaluates a single request against policy and returns a JSON decision.

### Usage

```sh
orca decide command --json '{"command":"<cmd>"}'
orca decide file    --json '{"path":"<p>","operation":"read|write"}'
orca decide prompt  --json '{"text":"<text>"}'
orca decide tool    --json '{"name":"<name>"}'

orca decide <kind> --stdin
orca decide <kind> --json <payload> [--ci]
orca decide <kind> --stdin [--ci]
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

- The command loads `.orca/policy.yaml`.
- `command` checks against policy command allow and deny rules.
- `file` checks file access rules using the supplied `operation`.
- `prompt` checks text for policy relevant content and redaction triggers.
- `tool` checks tool names against policy tool rules.
- If the request is malformed, the command returns a usage or general error.

### Exit codes

Policy outcomes for successful evaluation (JSON on stdout):

| Code | Decision | Meaning |
|------|----------|---------|
| `0` | `allow`, `context_only` | Permitted |
| `3` | `block` | Policy denied |
| `7` | `ask` | Approval required (non-interactive callers should read JSON) |
| `8` | `warn` | Redact or warn |

Failures before a decision is emitted:

| Code | Meaning |
|------|---------|
| `1` | General error (evaluation, parse, or internal failure) |
| `2` | Usage error |

Other Orca CLI commands also use `4` (`unsupported`), `5` (`child_failure`), and `6` (`redteam_failure`). Those codes are not returned for policy decisions above.

In `--ci` mode, `ask` is converted to `block` and exits with `3`.

### Examples

Allow a command:

```sh
orca decide command --json '{"command":"git status"}'
```

Check a file write:

```sh
orca decide file --json '{"path":"src/main.zig","operation":"write"}'
```

Check a prompt:

```sh
orca decide prompt --json '{"text":"Do not include secrets in the response."}'
```

Check a tool name from stdin:

```sh
printf '{"name":"edit"}' | orca decide tool --stdin
```

CI mode example:

```sh
orca decide command --json '{"command":"git push --force"}' --ci
```

In CI mode, any `ask` result becomes a deny path.

## `orca hook`

`orca hook` adapts host events to Orca policy decisions.

### Usage

```sh
orca hook codex SessionStart
orca hook codex UserPromptSubmit
orca hook codex PreToolUse
orca hook codex PermissionRequest
orca hook codex PostToolUse
orca hook codex Stop

orca hook claude SessionStart
orca hook claude UserPromptSubmit
orca hook claude PreToolUse
orca hook claude PermissionRequest
orca hook claude PostToolUse
orca hook claude SessionEnd
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

If the payload has `command`, Orca evaluates it as a command.

If the tool name matches a file tool and the payload has `path`, Orca evaluates it as a file write:

- `edit`
- `write`
- `file_write`
- `file_edit`
- `apply`
- `create_file`
- `write_file`

Otherwise, Orca treats the event as an MCP or tool request. In strict mode, that defaults to deny when policy does not allow it.

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
  "host_limitations": ["Hook enforcement is additive; does not replace orca run supervision."]
}
```

### Decision mapping

| Orca decision | Hook response |
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
printf '{"version":1,"host":"codex","event":"SessionStart","payload":{}}' | orca hook codex SessionStart
```

Prompt submit with a secret:

```sh
printf '{"version":1,"host":"claude","event":"UserPromptSubmit","payload":{"text":"my token is abc123"}}' | orca hook claude UserPromptSubmit
```

Tool request:

```sh
printf '{"version":1,"host":"codex","event":"PreToolUse","payload":{"name":"edit","path":"README.md"}}' | orca hook codex PreToolUse
```

CI mode:

```sh
printf '{"version":1,"host":"claude","event":"PermissionRequest","payload":{"command":"git push --force"}}' | orca hook claude PermissionRequest --ci
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

- In `orca decide`, `ask` becomes a non interactive deny path.
- In `orca hook`, `ask` becomes `block`.
- `warn` still returns warning output, but it does not become allow.
- CI mode does not add new policy rules. It only changes the fallback behavior for undecided actions.

## Error Handling

Common failures include:

- bad or missing JSON payloads
- invalid `kind`, `host`, or `event`
- unsupported payload shapes
- payloads over 256 KiB
- missing `.orca/policy.yaml`
- policy parse failures
- internal evaluation errors

`orca decide` uses the exit codes above so shell scripts and CI can gate on `$?` without parsing JSON. `orca hook` writes JSON to stdout and returns exit `0` for successful evaluation (including `block`, `ask`, and `warn`); hosts must read the JSON `decision` field. Hook returns non-zero only for usage, parse, or internal failures.

When possible, error responses should be explicit about the failed stage, but they should not print secrets or raw payloads.

## Limitations

- These commands are local policy adapters, not a sandbox.
- They only see the events and payloads the host provides.
- They cannot enforce actions the host never reports.
- File tool matching is based on known tool names and path presence.
- Network and MCP requests are only as visible as the host event stream makes them.
- Host hook enforcement is additive. It does not replace `orca run` supervision.
- `observe`, `context_only`, and similar non blocking responses are informational. A host may still choose its own final behavior.
