# Fake Hook Payloads

This directory explains the synthetic payloads used by the plugin demo.

The payloads themselves live in `tests/plugin-fixtures/`; this folder only points to them so the demo stays deterministic and easy to audit.

## Available payload references

### Codex

- `tests/plugin-fixtures/codex/session_start.json`
- `tests/plugin-fixtures/codex/user_prompt_submit_secret.json`
- `tests/plugin-fixtures/codex/permission_request.json`
- `tests/plugin-fixtures/codex/pre_tool_use_command_safe.json`
- `tests/plugin-fixtures/codex/pre_tool_use_command_dangerous.json`
- `tests/plugin-fixtures/codex/pre_tool_use_file_write_protected.json`
- `tests/plugin-fixtures/codex/post_tool_use.json`
- `tests/plugin-fixtures/codex/stop.json`

### Claude Code

- `tests/plugin-fixtures/claude/session_start.json`
- `tests/plugin-fixtures/claude/user_prompt_submit_secret.json`
- `tests/plugin-fixtures/claude/permission_request.json`
- `tests/plugin-fixtures/claude/pre_tool_use_command_safe.json`
- `tests/plugin-fixtures/claude/pre_tool_use_command_dangerous.json`
- `tests/plugin-fixtures/claude/pre_tool_use_file_write_protected.json`
- `tests/plugin-fixtures/claude/post_tool_use.json`
- `tests/plugin-fixtures/claude/session_end.json`

## Safety note

These fixtures are synthetic and local-only. Real secrets are never used in the demo.
