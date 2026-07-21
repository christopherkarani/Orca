# P04 — Claude Code Plugin Handoff

> Phase: P04
> Date: 2026-05-09
> Status: Complete

---

## Summary

Built the Orca Claude Code plugin package under `integrations/claude-code-plugin/` and the local marketplace catalog under `integrations/claude-marketplace/`. The plugin includes a manifest, five skills, a hooks configuration, README, marketplace files, integration documentation, and tests. All verification commands pass.

---

## Files Added

```text
integrations/claude-code-plugin/
  .claude-plugin/plugin.json
  skills/doctor/SKILL.md
  skills/init/SKILL.md
  skills/protect/SKILL.md
  skills/redteam/SKILL.md
  skills/replay/SKILL.md
  hooks/hooks.json
  README.md

integrations/claude-marketplace/
  .claude-plugin/marketplace.json
  README.md

docs/integrations/claude-code.md
tests/phase37_claude_plugin.zig
```

## Files Modified

```text
src/cli/plugin.zig
  - Updated test "plugin manifest claude reports expected path" to expect "exists"
    instead of "missing" now that the manifest file is present.

build.zig
  - Added phase36_codex_plugin_tests and phase37_claude_plugin_tests to the test suite.
```

---

## Skills Added

| Skill | Purpose |
|-------|---------|
| `doctor` | Check Orca installation, policy status, host integration status, and plugin readiness |
| `init` | Create or repair an Orca policy for the current repository |
| `protect` | Explain how to run the current Claude Code workflow under Orca protection |
| `redteam` | Run Orca red-team fixtures and summarize results |
| `replay` | Show and explain the latest Orca session replay |

No drone skills were added.
No MCP skills were added.

---

## Hooks Added

`integrations/claude-code-plugin/hooks/hooks.json` registers hooks for:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `SessionEnd`

Each hook calls `orca hook claude <event>` with a JSON payload on stdin.

Note: Claude Code uses `SessionEnd` instead of Codex's `Stop` event.

---

## Marketplace Status

A local marketplace catalog was added at:

```text
integrations/claude-marketplace/.claude-plugin/marketplace.json
```

This is a documented example only. Official marketplace availability is not yet implemented.

---

## Tests Run

### Plugin Structure Tests

```bash
zig test tests/phase37_claude_plugin.zig
```

Result: **27/27 passed**

Tests cover:
- Manifest exists, valid JSON, expected fields
- Skills exist, non-empty, reference real Orca commands
- No drone skill, no MCP skill
- Hooks exist, valid JSON, call `orca hook claude`
- No nonexistent scripts, no absolute paths
- Marketplace file valid JSON, points to claude plugin directory
- No fake secrets in plugin files
- README includes strongest-protection warning
- README states no MCP server behavior and no drone plugin features
- Docs do not claim official marketplace availability
- Docs do not claim MCP support
- Docs do not claim drone plugin support
- Hook fixtures still present

```bash
zig test tests/phase36_codex_plugin.zig
```

Result: **23/23 passed** (non-regression)

### Build Tests

```bash
zig build
```

Result: **Pass**

```bash
zig build test
```

Result: Pre-existing MCP proxy stdin hang still occurs. The phase36 and phase37 tests were added to build.zig and will run as part of the suite when the hang is resolved. Individual test binaries pass when run directly.

### Verification Commands

```bash
./zig-out/bin/orca plugin doctor claude
```
Result: Pass. Reports Claude Code plugin directory as "present".

```bash
./zig-out/bin/orca plugin manifest claude
```
Result: Pass. Reports manifest as "exists".

```bash
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/orca hook claude PreToolUse
```
Result: Pass. Returns `allow` decision.

```bash
cat tests/plugin-fixtures/claude/user_prompt_submit_secret.json \
  | ./zig-out/bin/orca hook claude UserPromptSubmit
```
Result: Pass. Returns `warn` decision with redaction.

```bash
./zig-out/bin/orca decide command --json '{"version":1,"host":"claude","command":"git status","mode":"strict"}'
```
Result: Pass. Returns `allow` decision.

```bash
./zig-out/bin/orca plugin doctor codex
```
Result: Pass. Non-regression verified.

```bash
./zig-out/bin/orca plugin manifest codex
```
Result: Pass. Non-regression verified.

```bash
./zig-out/bin/orca redteam --ci
```
Result: Pass. 10/10 fixtures passed, 100%.

```bash
./zig-out/bin/orca doctor
```
Result: Pass.

---

## Secret-Safety Result

- No raw secrets in plugin files.
- No raw secrets in generated hook outputs.
- No raw secrets in docs.
- No fake secret test values in plugin files.
- No obvious secret-like placeholders in plugin files.

---

## Separate Workstream / Drone Non-Regression Result

- No drone skills were added.
- No drone demos were added.
- No drone docs were added.
- No drone commands were exposed.
- The `orca plugin doctor` command still detects the separate drone workstream and reports safety mode active.
- Existing Edge tests were not modified.
- `edge redteam --ci` was not run because it is a separate binary and the plugin plan does not require it.

---

## Known Limitations

- Hooks are advisory; enforcement depends on Claude Code host support.
- The strongest protection remains `orca claude`.
- Plugin installation is preview/dry-run by default.
- Official marketplace availability is not yet implemented.
- The `orca plugin install` command does not yet perform actual host plugin installation.
- The marketplace catalog uses a relative path (`../claude-code-plugin`) which may need adjustment depending on the Claude Code version.

---

## Security Notes

- The Orca remains the source of truth.
- The plugin does not duplicate policy logic.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- The plugin does not claim stronger enforcement than Claude Code hooks support.
- No MCP config was added.
- No drone plugin features were added.

---

## Whether P05 Is Safe to Start

**Yes.** P05 (Plugin Security and Compatibility) is safe to start.

Rationale:
- P01 commands (`orca plugin doctor`, `orca plugin manifest`, `orca plugin install`) still work.
- P02 commands (`orca decide`, `orca hook`) still work.
- P03 Codex plugin files/tests still work.
- The Claude Code plugin does not conflict with the Codex plugin.
- No MCP config was added.
- No drone features were added.
- All tests pass or fail for pre-existing reasons only.

---

*End of P04 handoff.*
