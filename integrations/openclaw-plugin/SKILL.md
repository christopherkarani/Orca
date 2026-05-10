# Orca

Orca adds runtime guardrails to OpenClaw workflows via the Orca CLI. Use it when:

- You want policy-based command blocking before tool execution
- You need audit logging for agent sessions
- You want secret redaction in tool payloads
- You need permission request evaluation before user approval

## When to use Orca

| User intent | Use Orca? |
|-------------|-----------|
| "Run `rm -rf /`" | Yes — Orca blocks dangerous commands |
| "Let me run this shell script" | Yes — Orca evaluates against policy |
| "What time is it?" | No — safe query, no policy needed |
| "Execute this curl \| sh pipe" | Yes — Orca blocks known dangerous patterns |

## How it works

Orca registers lifecycle hooks that call the Orca CLI for policy decisions:

- `tool.before` — evaluates tool calls against policy before execution
- `permission.before` — evaluates permission requests before user approval
- `session.start`, `session.end` — informational logging
- `tool.after`, `permission.after` — audit logging

If a tool or permission is blocked, Orca throws an error that prevents execution.

## Prerequisites

- Orca CLI must be installed and available on `PATH`
- Run `orca doctor` to verify installation

## Example policy behavior

Safe command (`git status`):
```json
{
  "decision": "allow",
  "risk": "low",
  "reason": "policy_allow"
}
```

Dangerous command (`rm -rf *`):
```json
{
  "decision": "block",
  "risk": "high",
  "reason": "policy_deny",
  "message": "Blocked by Orca policy"
}
```

## Key behaviors

- **Thin wrapper**: All policy decisions are made by the Orca CLI
- **No duplicated logic**: The plugin does not reimplement policy
- **Secret redaction**: Keys matching `password`, `token`, `secret`, `api_key` are replaced with `[REDACTED]` before sending to Orca
- **Graceful degradation**: If Orca CLI is missing, the plugin warns and skips hooks
- **Honest limits**: Hooks are advisory; the strongest protection is `orca run -- openclaw`

## Don't use Orca for

- Replacing the Orca CLI (the CLI is the source of truth)
- Telemetry collection (no telemetry is collected)
- MCP server behavior (not included)
- Drone-specific features (not included)
