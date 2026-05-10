# Orca OpenClaw Plugin Integration

This document describes the Orca OpenClaw plugin, how to install it, and how to use it.

## Overview

The Orca OpenClaw plugin is a local integration package that adds Orca runtime guardrails to OpenClaw. It lives under `integrations/openclaw-plugin/` in the Orca repository.

The plugin is a thin layer. All policy decisions are made by the Orca CLI. The plugin does not duplicate policy logic.

The plugin provides native hooks and guardrails inside OpenClaw, routing lifecycle events through Orca policy for evaluation and logging.

## Strongest protection

The strongest protection for OpenClaw sessions is running the host through Orca:

```bash
orca run -- openclaw
```

The plugin adds native hooks and guardrails inside OpenClaw, but `orca run -- openclaw` is the strongest protection because the agent session itself is launched as an Orca-managed child process with filtered environment variables and full policy enforcement.

The strongest local protection remains running OpenClaw through `orca run -- openclaw`; the OpenClaw plugin provides native guardrails where OpenClaw plugin hooks support them.

## Prerequisites

- Orca CLI built and available in PATH (run `orca doctor` to verify)
- OpenClaw host installed

Orca must be installed separately. The plugin does not bundle the Orca CLI.

## Install instructions

### Local install

If you have OpenClaw installed locally:

```bash
openclaw plugins install ./integrations/openclaw-plugin
```

### npm install

After npm publication, install with:

```bash
openclaw plugins install npm:orca-openclaw-plugin
```

If OpenClaw supports bare npm package installs:

```bash
openclaw plugins install orca-openclaw-plugin
```

For local validation before publication, use `npm pack --dry-run`.

Verify the install with:

```bash
orca plugin doctor openclaw
openclaw plugins list --json
openclaw plugins doctor
```

### ClawHub install

The plugin is published to ClawHub as `orca-openclaw-plugin`.

```bash
openclaw plugins install clawhub:orca-openclaw-plugin
```

**Note:** The `clawhub:` install protocol requires a recent OpenClaw version. If your version does not support it, use the local path or npm install methods instead.

For submission details, see [openclaw-clawhub.md](openclaw-clawhub.md). For the readiness checklist, see [openclaw-clawhub-checklist.md](openclaw-clawhub-checklist.md).

### Build Orca

If you are installing from the Orca repository:

```bash
zig build
```

## Verify install

### Plugin doctor

```bash
orca plugin doctor openclaw
```

With JSON output:

```bash
orca plugin doctor openclaw --json
```

Expected output sections:
- Orca version
- Policy status (present/valid)
- Plugin directories (openclaw: found)
- Host binaries (openclaw: detected or not detected)

### Plugin manifest

```bash
orca plugin manifest openclaw
```

This reports the expected manifest path and existence status.

### Dry-run install

```bash
orca plugin install openclaw --dry-run
```

### Hook smoke test

```bash
cat tests/plugin-fixtures/openclaw/tool_command_safe.json \
  | orca hook openclaw tool.before
```

Expected: `allow` decision in valid JSON.

### Example decision command

```bash
orca decide command --json '{"version":1,"host":"openclaw","command":"git status","mode":"strict"}'
```

### Run redteam

```bash
orca redteam --ci
```

### Replay last session

```bash
orca replay --session last --verify
```

## Hooks supported

Hooks call `orca hook openclaw <event>` with a JSON payload on stdin. The following OpenClaw events are supported:

| OpenClaw Hook | Orca CLI Event | Description | Timeout |
|---------------|----------------|-------------|---------|
| `session_start` | `session.start` | Session initialization check | 10s |
| `before_tool_call` | `tool.before` | Tool use policy evaluation before execution | 15s |
| `after_tool_call` | `tool.after` | Post-tool acknowledgment and logging | 10s |
| `session_end` | `session.end` | Session end handling | 10s |

**Note:** OpenClaw does not expose dedicated permission hooks. Permission-like blocking is handled through `before_tool_call`.

### How hooks call Orca

Each hook sends a JSON payload to stdin and expects a JSON decision on stdout:

```bash
echo '{"version":1,"host":"openclaw","event":"tool.before","payload":{"tool":"shell","command":"git status","cwd":"/path/to/project"}}' \
  | orca hook openclaw tool.before
```

Example with a fixture file:

```bash
cat tests/plugin-fixtures/openclaw/tool_command_safe.json \
  | orca hook openclaw tool.before
```

## Uninstall

Remove the plugin from your OpenClaw configuration:

```bash
openclaw plugins uninstall orca
```

This plugin does not mutate host configuration beyond the plugin file itself, so uninstalling is safe.

## Troubleshooting

### Plugin directory not found

Ensure you run `orca plugin doctor openclaw` from the repository root or a project directory that contains the plugin. The doctor looks for `integrations/openclaw-plugin/`.

### Hooks timeout

If hooks exceed their timeout, OpenClaw may skip them. Check that `orca` is in PATH and that `.aegis/policy.yaml` loads quickly.

### Policy not found

Run `orca init --preset generic-agent` to create a default policy, then validate with `orca policy check .aegis/policy.yaml`.

### Orca binary not found

Build Orca with `zig build` or ensure `./zig-out/bin/orca` is in your PATH.

### Fake secret redaction questions

The plugin uses synthetic test secrets in fixtures only. If you see redaction warnings about these values in test output, that is expected behavior.

## Limitations

- Hooks are advisory; enforcement depends on OpenClaw host support.
- The strongest protection is `orca run -- openclaw`.
- Plugin installation is a preview/dry-run by default.
- No telemetry is collected.
- npm package `orca-openclaw-plugin@1.1.3` is published.
- ClawHub package `orca-openclaw-plugin@1.1.3` is published.
- The OpenClaw plugin does not add MCP server behavior or drone-specific plugin features.
- **Plugin ID mismatch warning:** OpenClaw may warn that the plugin manifest id (`orca`) differs from the npm package name (`orca-openclaw-plugin`). This is intentional: the manifest id must remain `orca` so that `openclaw plugins install clawhub:orca` resolves correctly. The warning is harmless and does not affect functionality.

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

This plugin does not add drone-specific plugin features. A separate drone workstream exists in this repository under `packages/edge/`. The Orca OpenClaw plugin does not expose or modify drone functionality.
