# P03 — Codex Plugin Handoff

> Phase: P03
> Date: 2026-05-09
> Status: Complete

---

## Summary

Built the Orca Codex plugin package under `integrations/codex-plugin/`. The plugin includes a manifest, five skills, a hooks configuration, README, tests, and integration documentation. All verification commands pass.

---

## Files Added

```text
integrations/codex-plugin/
  .codex-plugin/plugin.json
  skills/orca-doctor/SKILL.md
  skills/orca-init/SKILL.md
  skills/orca-protect/SKILL.md
  skills/orca-redteam/SKILL.md
  skills/orca-replay/SKILL.md
  hooks/hooks.json
  README.md
  examples/marketplace.json

docs/integrations/codex.md
tests/phase36_codex_plugin.zig
```

## Files Modified

```text
src/cli/plugin.zig
  - Updated test "plugin manifest codex reports expected path" to expect "exists"
    instead of "missing" now that the manifest file is present.

src/cli/hook.zig
  - Fixed permission classification in PermissionRequest handler to treat
    destructive file operations (delete, create, append, move, rename, remove)
    as file_write instead of file_read. This prevents under-classification of
    destructive operations that would otherwise be evaluated under read policy.
```

---

## Skills Added

| Skill | Purpose |
|-------|---------|
| `orca-doctor` | Check Orca installation, policy status, host integration status, and plugin readiness |
| `orca-init` | Create or repair an Orca policy for the current repository |
| `orca-protect` | Explain how to run the current Codex workflow under Orca protection |
| `orca-redteam` | Run Orca red-team fixtures and summarize results |
| `orca-replay` | Show and explain the latest Orca session replay |

No drone skills were added.
No MCP skills were added.

---

## Hooks Added

`integrations/codex-plugin/hooks/hooks.json` registers hooks for:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `Stop`

Each hook calls `orca hook codex <event>` with a JSON payload on stdin.

---

## Marketplace Status

A documented example marketplace file was added at:

```text
integrations/codex-plugin/examples/marketplace.json
```

This is an example only. Official marketplace availability is not yet implemented.

---

## Tests Run

### Plugin Structure Tests

```bash
zig test tests/phase36_codex_plugin.zig
```

Result: **23/23 passed**

Tests cover:
- Manifest exists, valid JSON, expected fields
- Skills exist, non-empty, reference real Orca commands
- No drone skill, no MCP skill
- Hooks exist, valid JSON, call `orca hook codex`
- No nonexistent scripts, no absolute paths
- Marketplace example valid JSON
- No fake secrets in plugin files
- README includes strongest-protection warning
- README states no MCP server behavior and no drone plugin features
- Docs do not claim official marketplace availability
- Hook fixtures still present

### Build Tests

```bash
zig build
```

Result: **Pass**

```bash
zig build test
```

Result: 266/273 passed, 1 failed (pre-existing MCP proxy stdin hang), 6 skipped. The single failure is the known pre-existing MCP proxy test issue documented in the P02 handoff. The Codex plugin changes did not introduce new test failures.

### Verification Commands

```bash
./zig-out/bin/orca plugin doctor codex
```
Result: Pass. Reports codex plugin directory as "present".

```bash
./zig-out/bin/orca plugin manifest codex
```
Result: Pass. Reports manifest as "exists".

```bash
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json \
  | ./zig-out/bin/orca hook codex PreToolUse
```
Result: Pass. Returns `allow` decision.

```bash
cat tests/plugin-fixtures/codex/user_prompt_submit_secret.json \
  | ./zig-out/bin/orca hook codex UserPromptSubmit
```
Result: Pass. Returns `warn` decision with redaction.

```bash
./zig-out/bin/orca decide command --json '{"command":"git status"}'
```
Result: Pass. Returns `allow` decision.

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

- Hooks are advisory; enforcement depends on Codex host support.
- The strongest protection remains `orca run -- <codex-command>`.
- Plugin installation is preview/dry-run by default.
- Official marketplace availability is not yet implemented.
- The `orca plugin install` command does not yet perform actual host plugin installation.

---

## Security Notes

- The Orca remains the source of truth.
- The plugin does not duplicate policy logic.
- Hook stdout is host-valid JSON.
- Human logs go to stderr.
- CI mode never prompts.
- The plugin does not claim stronger enforcement than Codex hooks support.
- Post-review fix: destructive file operations in PermissionRequest are now correctly classified as `file_write` (not `file_read`).

---

## Whether P04 Is Safe to Start

**Yes.** P04 (Claude Code plugin) is safe to start.

Rationale:
- P01 commands (`orca plugin doctor`, `orca plugin manifest`, `orca plugin install`) still work.
- P02 commands (`orca decide`, `orca hook`) still work.
- The Codex plugin does not conflict with Claude Code plugin space (`integrations/claude-code-plugin/`).
- No MCP config was added.
- No drone features were added.
- All tests pass or fail for pre-existing reasons only.

---

*End of P03 handoff.*
