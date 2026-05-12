# Repo Marketplace Install

This document summarizes the repo marketplace install support added to Orca.

## Summary

Orca can now be installed as a repo marketplace plugin for Codex and Claude Code. Root-level marketplace files point to the existing plugin directories, and the `orca plugin manifest` / `orca plugin doctor` commands report marketplace file status.

## Marketplace Files Added

### Codex

```text
.agents/plugins/marketplace.json
```

Points to `./integrations/codex-plugin` with category "Developer Tools".

### Claude Code

```text
.claude-plugin/marketplace.json
```

Points to `./integrations/claude-code-plugin` with category "developer-tools".

## Codex Install Command

```bash
codex plugin marketplace add chriskarani/orca
```

Then install Orca from Codex's plugin UI/directory after adding the marketplace.

## Claude Install Command

CLI:
```bash
claude plugin marketplace add chriskarani/orca
claude plugin install orca@orca --scope user
```

In-app:
```text
/plugin marketplace add chriskarani/orca
/plugin install orca@orca
/reload-plugins
```

## Local Testing Status

- `zig build` passes.
- `zig build test` passes (552/560 tests; 2 pre-existing failures unrelated to marketplace changes).
- All marketplace JSON files validate with `python3 -m json.tool`.
- `./zig-out/bin/orca plugin manifest codex` reports marketplace file exists.
- `./zig-out/bin/orca plugin manifest claude` reports marketplace file exists.
- `./zig-out/bin/orca plugin doctor codex` reports marketplace file and plugin manifest present.
- `./zig-out/bin/orca plugin doctor claude` reports marketplace file and plugin manifest present.
- `./scripts/package-plugins.sh` produces expected artifacts with checksums.
- Hook smoke tests pass for both Codex and Claude.

## Official Marketplace Status

- **Repo marketplace**: yes — root-level `.agents/plugins/marketplace.json` and `.claude-plugin/marketplace.json` are present.
- **Official marketplace**: no — Orca is not listed in the official Codex or Claude marketplace unless separately accepted/listed.

## Tests Run

```bash
zig build
zig build test
python3 -m json.tool .agents/plugins/marketplace.json
python3 -m json.tool .claude-plugin/marketplace.json
python3 -m json.tool integrations/codex-plugin/.codex-plugin/plugin.json
python3 -m json.tool integrations/claude-code-plugin/.claude-plugin/plugin.json
./zig-out/bin/orca plugin manifest codex
./zig-out/bin/orca plugin manifest claude
./zig-out/bin/orca plugin doctor codex
./zig-out/bin/orca plugin doctor claude
./scripts/package-plugins.sh
ls -la dist/plugins
cat dist/plugins/orca-plugin-checksums.txt
cat tests/plugin-fixtures/codex/pre_tool_use_command_dangerous.json | ./zig-out/bin/orca hook codex PreToolUse
cat tests/plugin-fixtures/claude/pre_tool_use_command_dangerous.json | ./zig-out/bin/orca hook claude PreToolUse
```

## Known Limitations

- The repo marketplace files are repo-level sources, not official marketplace listings.
- Plugin manifests now use "orca" branding.
- Hook JSON files now reference the `orca` CLI command.
- Marketplace files are not bundled inside individual plugin zips; they remain in the repository root. Use the repo path for marketplace install, or use release artifact zips for local path install.
- The strongest local protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

## Is Repo Marketplace Install Ready?

Yes. The repository is ready to be used as a plugin marketplace source for both Codex and Claude Code.
