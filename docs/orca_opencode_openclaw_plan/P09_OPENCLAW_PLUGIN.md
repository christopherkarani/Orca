# P09 — OpenClaw Plugin

## Objective

Build a native OpenClaw plugin wrapper for Orca.

At the end of this phase, the repo should contain a local OpenClaw plugin that calls the Orca CLI for policy decisions and diagnostics.

---

## Recommended Effort

```text
High
```

OpenClaw is a new host integration and has a different plugin model than Codex, Claude Code, and OpenCode.

---

## Scope

Create:

```text
integrations/openclaw-plugin/
  openclaw.plugin.json
  package.json
  src/
    index.ts
  dist/
    index.js
    index.d.ts
  README.md
```

Add CLI support:

```bash
orca plugin doctor openclaw
orca plugin manifest openclaw
orca plugin install openclaw --dry-run
orca hook openclaw <event>
```

---

## Non-goals

Do not publish to npm in this phase.

Do not publish to ClawHub in this phase.

Do not bundle the Orca Zig CLI.

Do not add MCP behavior.

Do not add drone plugin behavior.

Do not modify OpenClaw itself.

---

## OpenClaw Plugin Manifest

Create:

```text
integrations/openclaw-plugin/openclaw.plugin.json
```

It should include at least:

```json
{
  "id": "orca",
  "name": "Orca",
  "version": "1.0.0",
  "description": "Runtime guardrails for OpenClaw workflows via the Orca CLI.",
  "configSchema": {
    "type": "object",
    "properties": {},
    "additionalProperties": false
  }
}
```

Adjust to current OpenClaw native plugin schema.

OpenClaw docs require native plugins to ship `openclaw.plugin.json` with inline `configSchema`, even if empty.

---

## Package Metadata

Create `package.json` for local development:

```json
{
  "name": "@orca/openclaw-plugin",
  "version": "1.0.0",
  "type": "module",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "openclaw": {
    "extensions": ["./src/index.ts"],
    "runtimeExtensions": ["./dist/index.js"]
  }
}
```

For packaged npm installs, runtime JS output must exist and `runtimeExtensions` should map to built files.

---

## Plugin Behavior

The OpenClaw plugin should:

- initialize safely
- check whether `orca` is available
- call `orca plugin doctor openclaw`
- call `orca decide ...` or `orca hook openclaw ...`
- not duplicate Orca policy logic
- not persist raw secrets
- not provide drone-specific functionality
- not add MCP behavior
- fail gracefully if Orca is missing

Because OpenClaw’s exact runtime hook API may evolve, implement the minimum plugin entry that can be validated locally and document limitations.

---

## Hook Adapter

Add `orca hook openclaw <event>` support for the OpenClaw events you can model safely.

Start with generic event categories:

```text
tool.before
tool.after
permission.before
permission.after
session.start
session.end
```

If current OpenClaw docs expose different exact hook names, use those.

The adapter should:

- read JSON from stdin
- bound input size
- redact before persistence
- emit valid JSON
- never prompt in CI
- classify risky commands/files/tools
- not include drone decisions

---

## Tests

Create fixtures:

```text
tests/plugin-fixtures/openclaw/
  session_start.json
  tool_command_safe.json
  tool_command_dangerous.json
  tool_file_write_protected.json
  permission_request.json
  session_end.json
```

Add tests for:

- manifest exists
- manifest valid JSON
- configSchema exists
- package.json valid
- openclaw field exists
- source file exists
- dist file exists or build target exists
- plugin calls Orca CLI
- plugin does not include MCP behavior
- plugin does not include drone behavior
- fixtures work with `orca hook openclaw`
- existing Codex/Claude/OpenCode plugins still pass

---

## Docs

Create:

```text
docs/integrations/openclaw.md
```

Include:

- overview
- local install
- npm install planned
- ClawHub submission planned
- `orca run -- openclaw` strongest-protection wording
- plugin limitations
- no MCP behavior
- no drone plugin behavior
- troubleshooting

Required wording:

```text
The strongest local protection remains running OpenClaw through `orca run -- openclaw`; the OpenClaw plugin provides native guardrails where OpenClaw plugin hooks support them.
```

---

## Commands to Run

```bash
zig build
zig build test

./zig-out/bin/orca plugin doctor openclaw
./zig-out/bin/orca plugin manifest openclaw
./zig-out/bin/orca plugin install openclaw --dry-run

cat tests/plugin-fixtures/openclaw/tool_command_dangerous.json \
  | ./zig-out/bin/orca hook openclaw tool.before
```

If OpenClaw is installed locally:

```bash
openclaw plugins install ./integrations/openclaw-plugin
openclaw plugins list --json
openclaw plugins doctor
```

Skip local OpenClaw validation if OpenClaw is not installed.

---

## Acceptance Criteria

- OpenClaw plugin directory exists.
- `openclaw.plugin.json` exists and validates.
- package metadata exists.
- plugin source exists.
- built runtime output exists or build target exists.
- Orca CLI supports `plugin doctor openclaw`.
- Orca CLI supports `hook openclaw`.
- docs exist.
- no MCP behavior.
- no drone plugin behavior.
- no secrets.
- existing plugin tests still pass.

---

## Deliverable

Create or update:

```text
docs/integrations/p09-openclaw-plugin.md
```

Include:

- summary
- plugin files added
- hook adapter status
- tests run
- local OpenClaw validation result if attempted
- known limitations
- whether P10 is safe to start

---

## Handoff

At the end, provide:

- files changed
- tests run
- OpenClaw plugin status
- hook adapter status
- package status
- docs status
- known limitations
- whether P10 is safe to start
