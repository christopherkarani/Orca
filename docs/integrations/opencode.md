# Orca OpenCode Plugin Integration

This document describes the Orca OpenCode plugin, how to install it, and how to use it.

## Overview

The Orca OpenCode plugin is a local integration package that adds Orca skills and lifecycle hooks to OpenCode. It lives under `integrations/opencode-plugin/` in the Orca repository.

The plugin is a thin layer. All policy decisions are made by the Orca CLI. The plugin does not duplicate policy logic.

The plugin provides native hooks and guardrails inside OpenCode, routing lifecycle events through Orca policy for evaluation and logging.

## Strongest protection

The strongest protection for OpenCode sessions is running the host through Orca:

```bash
orca run -- opencode
```

The plugin adds native hooks and guardrails inside OpenCode, but `orca run -- opencode` is the strongest protection because the agent session itself is launched as an Orca-managed child process with filtered environment variables and full policy enforcement.

## Prerequisites

- Orca CLI built and available in PATH
- Zig 0.15.2 (to build Orca from source)
- OpenCode host binary installed

## Install instructions

### Build Orca

```bash
zig build
```

### Local project install

Install the plugin into the current project:

```text
.opencode/plugins/orca.ts
```

OpenCode loads plugins from `.opencode/plugins/` relative to the workspace root when running inside a project directory.

### Global install

Install the plugin for all OpenCode sessions:

```text
~/.config/opencode/plugins/orca.ts
```

OpenCode loads global plugins from `~/.config/opencode/plugins/` when no project-local plugin is present.

### Optional npm distribution

Official npm distribution is not yet implemented. Use the local path or global config install paths above until a published package is available.

### Manual fallback install

If your OpenCode version does not support automatic plugin loading:

1. Copy the skills from `integrations/opencode-plugin/skills/` into your OpenCode skills directory.
2. Copy the hooks from `integrations/opencode-plugin/hooks/hooks.json` into your OpenCode hooks configuration.
3. Ensure `orca` is in PATH or use the full path to the binary.

## Verify install

### Plugin doctor

```bash
orca plugin doctor opencode
```

With JSON output:

```bash
orca plugin doctor opencode --json
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (opencode: found)
- Host binaries (opencode: detected or not detected)

### Plugin manifest

```bash
orca plugin manifest opencode
```

This reports the expected manifest path and existence status.

### Dry-run install

```bash
orca plugin install opencode --dry-run
```

### Hook smoke test

```bash
cat tests/plugin-fixtures/opencode/tool_execute_before_command_safe.json \
  | orca hook opencode tool.execute.before
```

Expected: `allow` decision in valid JSON.

### Example decision command

```bash
orca decide command --json '{"version":1,"host":"opencode","command":"git status","mode":"strict"}'
```

### Run redteam

```bash
orca redteam --ci
```

### Replay last session

```bash
orca replay --session last --verify
```

## Skill list

| Skill | File | Purpose |
|-------|------|---------|
| `orca-doctor` | `skills/orca-doctor/SKILL.md` | Check installation and readiness |
| `orca-init` | `skills/orca-init/SKILL.md` | Create or repair a policy |
| `orca-protect` | `skills/orca-protect/SKILL.md` | Explain strongest protection |
| `orca-redteam` | `skills/orca-redteam/SKILL.md` | Run red-team fixtures |
| `orca-replay` | `skills/orca-replay/SKILL.md` | Replay latest session |

## Hooks supported

Hooks call `orca hook opencode <event>` with a JSON payload on stdin. The following OpenCode events are supported:

| Event | Description | Timeout |
|-------|-------------|---------|
| `session.created` | Session initialization check | 10s |
| `tool.execute.before` | Tool use policy evaluation before execution | 15s |
| `tool.execute.after` | Post-tool acknowledgment and logging | 10s |
| `permission.asked` | Permission request policy evaluation | 15s |
| `permission.replied` | Permission response logging | 10s |
| `file.edited` | File edit policy evaluation and logging | 10s |
| `command.executed` | Shell command execution logging | 10s |
| `session.updated` | Session state update logging | 10s |
| `session.idle` | Session idle event handling | 10s |
| `session.error` | Session error logging | 10s |
| `shell.env` | Environment variable inspection and redaction | 10s |

### How hooks call Orca

Each hook sends a JSON payload to stdin and expects a JSON decision on stdout:

```bash
echo '{"version":1,"host":"opencode","event":"tool.execute.before","payload":{"tool":"shell","command":"git status","cwd":"/path/to/project"}}' \
  | orca hook opencode tool.execute.before
```

Example with a fixture file:

```bash
cat tests/plugin-fixtures/opencode/tool_execute_before_command_safe.json \
  | orca hook opencode tool.execute.before
```

## Uninstall

Remove the plugin from your OpenCode configuration:

1. Delete the local project plugin:
   ```bash
   rm .opencode/plugins/orca.ts
   ```

2. Or delete the global plugin:
   ```bash
   rm ~/.config/opencode/plugins/orca.ts
   ```

This plugin does not mutate host configuration beyond the plugin file itself, so uninstalling is safe.

## Troubleshooting

### Plugin directory not found

Ensure you run `orca plugin doctor opencode` from the repository root or a project directory that contains the plugin. The doctor looks for `.opencode/plugins/orca.ts` (local) or `~/.config/opencode/plugins/orca.ts` (global).

### Hooks timeout

If hooks exceed their timeout, OpenCode may skip them. Check that `orca` is in PATH and that `.aegis/policy.yaml` loads quickly.

### Policy not found

Run `orca init --preset generic-agent` to create a default policy, then validate with `orca policy check .aegis/policy.yaml`.

### Orca binary not found

Build Orca with `zig build` or ensure `./zig-out/bin/orca` is in your PATH.

### Fake secret redaction questions

The plugin uses synthetic test secrets (e.g., `fake_p05_secret_value`) in fixtures only. If you see redaction warnings about these values in test output, that is expected behavior.

## Limitations

- Hooks are advisory; enforcement depends on OpenCode host support.
- The strongest protection is `orca run -- opencode`.
- Plugin installation is a preview/dry-run by default.
- Official npm distribution is not yet implemented.

## Security model

- The Orca CLI is the source of truth.
- The plugin does not reimplement policy logic.
- No secrets are stored in plugin files.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.

## No telemetry

This plugin does not collect telemetry. No usage data, session content, or metadata is transmitted to any external service.

## No MCP behavior

This plugin does not add MCP server behavior.

## No drone features

This plugin does not add drone-specific plugin features. A separate drone workstream exists in this repository under `packages/edge/`. The Orca OpenCode plugin does not expose or modify drone functionality.
