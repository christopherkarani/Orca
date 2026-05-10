# Plugin Compatibility Matrix

This document describes feature compatibility across the Orca CLI and host plugins.

## Feature Matrix

| Feature | Orca CLI | Codex Plugin | Claude Code Plugin | OpenCode Plugin | OpenClaw Plugin |
|---------|-----------|--------------|-------------------|-----------------|-----------------|
| plugin doctor | yes | calls CLI | calls CLI | calls CLI | calls CLI |
| manifest status | yes | yes | yes | yes | yes |
| install dry-run | yes | yes | yes | yes | yes |
| skills | n/a | yes | yes | n/a | n/a |
| hooks | n/a | yes | yes | yes | yes |
| decision API | yes | calls CLI | calls CLI | calls CLI | calls CLI |
| MCP server behavior | no | no | no | no | no |
| drone plugin features | no | no | no | no | no |
| telemetry | no | no | no | no | no |

## Command Compatibility

| Command | Orca CLI | Codex Plugin | Claude Code Plugin | OpenCode Plugin | OpenClaw Plugin |
|---------|-----------|--------------|-------------------|-----------------|-----------------|
| `orca plugin doctor` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca plugin manifest` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca plugin install --dry-run` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca decide` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca hook` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca redteam --ci` | native | calls CLI | calls CLI | calls CLI | calls CLI |
| `orca replay` | native | calls CLI | calls CLI | calls CLI | calls CLI |

## Host Limitations

### Codex

- Hooks are advisory; enforcement depends on Codex host support.
- Actual plugin loading mechanism depends on Codex version.
- Event names: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop`.

### Claude Code

- Hooks are advisory; enforcement depends on Claude Code host support.
- Actual plugin loading mechanism depends on Claude Code version.
- Event names: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionEnd`.

### OpenCode

- Hooks are advisory; enforcement depends on OpenCode host support.
- Actual plugin loading mechanism depends on OpenCode version.
- OpenCode uses hooks, not skills.
- Event names: `session.created`, `tool.execute.before`, `tool.execute.after`, `permission.asked`, `permission.replied`, `file.edited`, `command.executed`, `session.updated`, `session.idle`, `session.error`, `shell.env`.

### OpenClaw

- Hooks are advisory; enforcement depends on OpenClaw host support.
- Actual plugin loading mechanism depends on OpenClaw version.
- OpenClaw uses hooks, not skills.
- Event names: `session.start`, `tool.before`, `tool.after`, `permission.before`, `permission.after`, `session.end`.
- npm package: planned in P10
- ClawHub submission: planned in P11

## Version Compatibility

| Component | Version | Minimum Orca CLI |
|-----------|---------|-------------------|
| Orca core | 1.1.0 | 1.0.0 |
| Codex plugin | 1.1.0 | 1.0.0 |
| Claude Code plugin | 1.1.0 | 1.0.0 |
| OpenCode plugin | 1.1.0 | 1.0.0 |
| OpenClaw plugin | 1.0.0 | 1.0.0 |

Orca plugins 1.x require Orca CLI >= 1.0.0.

## Platform Support

All plugin features work on the same platforms as the Orca CLI:

| Platform | Orca CLI | Codex Plugin | Claude Code Plugin | OpenCode Plugin | OpenClaw Plugin |
|----------|-----------|--------------|-------------------|-----------------|-----------------|
| macOS (arm64) | yes | yes | yes | yes | yes |
| macOS (x86_64) | yes | yes | yes | yes | yes |
| Linux (x86_64) | yes | yes | yes | yes | yes |
| Linux (arm64) | yes | yes | yes | yes | yes |
| Windows (x86_64) | yes | yes | yes | yes | yes |

## Marketplace Support

| Marketplace Type | Codex | Claude Code | OpenCode | OpenClaw |
|------------------|-------|-------------|----------|----------|
| Repo marketplace | `.agents/plugins/marketplace.json` | `.claude-plugin/marketplace.json` | n/a | n/a |
| Official marketplace | not yet listed | not yet listed | n/a | planned in P11 |
| npm package | n/a | n/a | published | planned in P10 |

Repo marketplace files point to the local plugin directories:
- Codex: `integrations/codex-plugin/`
- Claude Code: `integrations/claude-code-plugin/`
- OpenClaw: `integrations/openclaw-plugin/`

These are repo marketplace sources, not official marketplace listings.

## What Is Not Supported

| Feature | Status | Notes |
|---------|--------|-------|
| MCP server behavior | not included | Future work if explicitly needed |
| Drone plugin features | not included | Separate workstream, out of scope |
| Telemetry | not included | No phone-home behavior |
| SaaS requirement | not included | All operations are local |
| Official marketplace | not yet implemented | Repo marketplace is available; official listing is separate |
| OpenClaw npm package | planned in P10 | Not yet published |
| OpenClaw ClawHub submission | planned in P11 | Not yet submitted |

## See Also

- `docs/integrations/orca-cli-plugin.md`
- `docs/integrations/codex.md`
- `docs/integrations/claude-code.md`
- `docs/integrations/opencode.md`
- `docs/integrations/plugin-security-model.md`
