# Heredoc Block Message Design

This document defines the human-readable and JSON error message formats for
heredoc and inline-script blocking. The goal is to be clear, actionable, and
safe-by-default (no secret leakage).

## Goals

- Explain *why* the heredoc was blocked in plain language.
- Provide stable identifiers for allowlisting.
- Show a small context window around the match.
- Avoid leaking secrets (redaction + truncation rules).
- Preserve behavior in non-TTY environments (no ANSI).

## Non-Goals

- Full source rendering or syntax highlighting.
- Perfect language detection in edge cases.

## Human-Readable Format (stderr)

### Header

```
BLOCKED: Destructive pattern in heredoc
```

### Details

```
Language:   <language>
Rule ID:    <pack_id:pattern_name>
Reason:     <short reason>
Matched:    <matched snippet>
Line:       <line number in heredoc>
Severity:   <deny|warn>
```

### Context Window

Show a small window with the offending line highlighted:

```
Context:
  1| import os
  2| path = "/tmp/data"
> 3| os.system("rm -rf /tmp/data")
  4| print("done")
```

### Suggestions

```
Suggestions:
- <safe alternative 1>
- <safe alternative 2>
- If intentional: orca allow <rule-id> -r "reason"
```

### Example

```
BLOCKED: Destructive pattern in heredoc
Language:   python
Rule ID:    heredoc.python.os_system
Reason:     os.system() executes shell commands
Matched:    os.system("rm -rf /tmp/data")
Line:       3
Severity:   deny

Context:
  1| import os
  2| path = "/tmp/data"
> 3| os.system("rm -rf /tmp/data")
  4| print("done")

Suggestions:
- Use subprocess with explicit arguments instead
- If intentional: orca allow heredoc.python.os_system -r "reason"
```

## JSON Format (stdout)

For the Claude Code hook protocol:

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "deny",
    "reason": "Heredoc contains destructive pattern: os.system() executes shell commands",
    "details": {
      "detection_type": "heredoc",
      "language": "python",
      "rule_id": "heredoc.python.os_system",
      "matched_text": "os.system(\"rm -rf /tmp/data\")",
      "line_in_heredoc": 3,
      "severity": "deny",
      "suggestions": [
        "Use subprocess with explicit arguments instead",
        "If intentional: orca allow heredoc.python.os_system -r \"reason\""
      ]
    }
  }
}
```

### JSON Requirements

- `permissionDecision` must be `deny` for blocks.
- `reason` should be concise and user-friendly.
- `details.rule_id` must be a stable allowlist key.
- `details.matched_text` must be redacted/truncated.
- `details.suggestions` should include at least one actionable step.

## Redaction and Truncation Rules

- Redact quoted strings by default for logs in non-TTY output.
- Truncate `matched_text` to 120 chars (configurable).
- Always preserve rule ID and reason; never redact those.
- Context lines should be truncated to 160 chars each.

## Context Extraction Rules

- Window size: 2 lines before and after the matched line.
- If at file boundaries, show only available lines.
- Use 1-based line numbers within the heredoc payload.

## Decision Mapping

- **Critical/High** -> `deny`
- **Medium** -> `warn` unless a catastrophic literal target is detected
- **Low** -> `log` (no block)

## Testing Checklist

- Valid JSON payload on deny (hook protocol compliance).
- Context extraction respects boundaries.
- Redaction/truncation applied to matched text and context.
- Non-TTY output contains no ANSI.
- Allowlist suggestion uses the correct rule ID.

