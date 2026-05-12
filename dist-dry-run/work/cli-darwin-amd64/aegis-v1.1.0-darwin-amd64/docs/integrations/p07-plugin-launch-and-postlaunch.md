# P07 — Plugin Launch and Post-Launch

## Summary

This phase prepared the Aegis plugin system for public launch and post-launch triage. All launch documents, issue templates, demo instructions, triage docs, and release checklists were created or updated. The plugin artifacts were built, packaged, and verified.

---

## Release Notes Status

**File:** `PLUGIN_RELEASE_NOTES.md`

**Status:** Created

**Contents:**
- Version 1.1.0
- Aegis CLI plugin surface overview
- Codex plugin summary
- Claude Code plugin summary
- Installation instructions (release artifact, local path, checksum verification)
- Verification commands
- Demo link
- Security model with required wording:
  > "The strongest protection remains running the agent through `aegis run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts."
- Known limitations
- Checksum information
- Vulnerability reporting (links to SECURITY.md)
- Contribution guidance
- Troubleshooting links
- Required exclusion wording:
  > "These plugins do not add MCP server functionality or drone-specific plugin features."

**Overclaim check:** No claims of perfect sandboxing, universal transparent enforcement, official marketplace availability, MCP support, drone support, or SaaS.

---

## Launch Docs Status

**File:** `LAUNCH_PLUGINS.md`

**Status:** Created

**Contents:**
- Short launch announcement
- What Aegis plugins are
- Why they exist
- Codex and Claude Code plugin summaries
- Install links
- Demo flow
- Limitations
- Security model
- Contribution ask
- Issue reporting instructions
- Launch post drafts for GitHub release, Hacker News/Reddit, X/LinkedIn, developer/security communities

---

## Demo Status

**Directory:** `examples/plugin-demo/`

**Status:** Created

**Files:**
- `README.md` — overview with exact required deterministic-demo wording
- `codex-demo.md` — Codex-specific walkthrough with fixture references
- `claude-demo.md` — Claude-specific walkthrough with fixture references
- `fake-hook-payloads/README.md` — synthetic payload index referencing `tests/plugin-fixtures/`

**Demo requires:** No real LLM, no real Codex session, no real Claude Code session, no external network, no real secrets, no drone hardware, no MCP server.

---

## Issue Templates Status

**Directory:** `.github/ISSUE_TEMPLATE/`

**Status:** Created (6 templates)

**Files:**
- `codex_plugin_bug.md`
- `claude_plugin_bug.md`
- `aegis_cli_plugin_bug.md`
- `plugin_security_bug.md` — includes exact required wording: "Do not paste real secrets, tokens, credentials, or private keys into this issue."
- `plugin_compatibility.md`
- `plugin_docs_issue.md`

All templates request: Aegis version, plugin version, OS, host tool version, install method, command run, expected/actual behavior, sanitized logs, diagnostic checkboxes.

---

## Triage Docs Status

**File:** `docs/integrations/plugin-triage.md`

**Status:** Created

**Contents:**
- Recommended labels (exact wording): `plugin:codex`, `plugin:claude`, `plugin:cli`, `plugin:hooks`, `plugin:install`, `plugin:marketplace`, `plugin:security`, `plugin:compatibility`, `plugin:docs`, `plugin:packaging`, `plugin:release`
- Severity guidance (exact wording):
  - P0: secret leakage, unsafe decision downgrade, hook output corrupts host protocol
  - P1: install broken, hooks not firing, false security claim, release artifact broken
  - P2: docs confusion, compatibility gap, non-critical false positive
  - P3: enhancement request
- Triage process description
- Note: labels are not added through API

---

## Post-Launch Patch Checklist Status

**File:** `docs/integrations/plugin-postlaunch-patch-checklist.md`

**Status:** Created

**Contents:**
- First 24-hour triage process
- First 72-hour triage process
- When to cut `vX.Y.1` criteria
- Security patch criteria
- Install bug patch criteria
- Docs patch criteria
- Host compatibility patch criteria
- Release rollback notes
- What data to collect without telemetry
- How to ask users for bug reports safely
- No telemetry by default statement

---

## Plugin Release Checklist Status

**File:** `docs/integrations/plugin-release-checklist.md`

**Status:** Created

**Contents:**
- Build and tests: `zig build`, `zig build test`, plugin security tests
- Packaging: package plugins, verify checksums, verify artifact contents, verify no secrets/MCP config/drone files
- Docs: verify links, issue templates, release notes, demo, known limitations, README section, no overclaiming
- Runtime smoke tests: plugin doctor for both hosts, fake hook payloads

---

## README Update Status

**File:** `README.md`

**Status:** Updated

Added "Agent Host Plugins" section with links to:
- Codex plugin docs
- Claude Code plugin docs
- Plugin security model
- Plugin troubleshooting

Includes required wording about strongest local protection.

---

## Package Status

**Command:** `./scripts/package-plugins.sh`

**Result:** Success

**Artifacts produced:**
- `dist/plugins/aegis-codex-plugin-v1.1.0.zip`
- `dist/plugins/aegis-claude-code-plugin-v1.1.0.zip`
- `dist/plugins/aegis-claude-marketplace-v1.1.0.zip`
- `dist/plugins/aegis-plugin-checksums.txt`

**Secret scan:** Passed — "No obvious secrets found in artifacts."

---

## Checksum Status

**File:** `dist/plugins/aegis-plugin-checksums.txt`

**Status:** Generated and verified

```
57e0e44e91589376880fc56ff2319b4f2a4babec29bee58f36503312f91aa17f  aegis-claude-code-plugin-v1.1.0.zip
5e056e7211b822a990cffb42b3e0367c3161e133bbdb5c45d7d9c4ccff921a42  aegis-claude-marketplace-v1.1.0.zip
d9a4fbb99d3ccc22aaabc08ee1506102aa5200636d038cbf3bfe483eb8b338a2  aegis-codex-plugin-v1.1.0.zip
```

---

## Secret Scan Result

**Method:** `grep` + `package-plugins.sh` built-in scan

**Scopes scanned:**
- `integrations/codex-plugin/`
- `integrations/claude-code-plugin/`
- `integrations/claude-marketplace/`
- `docs/integrations/`
- `examples/plugin-demo/`
- `.github/ISSUE_TEMPLATE/`
- `dist/plugins/`
- `PLUGIN_RELEASE_NOTES.md`
- `LAUNCH_PLUGINS.md`
- `README.md`

**Findings:**
- Only synthetic test secrets found: `fake_p05_secret_value` in `tests/plugin-fixtures/codex/user_prompt_submit_secret.json` and `tests/plugin-fixtures/claude/user_prompt_submit_secret.json` — these are intentional fake values.
- No raw secrets in plugin artifacts, docs, demo output, issue templates, release notes, or launch announcement.
- No real credentials, API keys, tokens, or private keys.

**Result:** Pass

---

## Docs Overclaim Result

**Method:** Manual review of all new and updated docs

**Findings:**
- All docs include the required wording about strongest protection.
- No claims of perfect sandboxing.
- No claims of universal transparent file/network enforcement.
- No claims of protection for agents not launched through Aegis.
- No claims of protection against root/admin/kernel compromise.
- No claims of protection against users approving unsafe actions.
- No MCP support claims.
- No drone plugin support claims.
- No official marketplace availability claims.
- No SaaS or telemetry claims.

**Result:** Pass — no overclaiming detected.

---

## Optional Local Host Validation

**Codex:**
- Host binary detected in PATH by `aegis plugin doctor codex`.
- Plugin directory found.
- Manifest exists.

**Claude Code:**
- Host binary detected in PATH by `aegis plugin doctor claude`.
- Plugin directory found.
- Manifest exists.

**Note:** Actual host plugin loading depends on Codex/Claude Code version and plugin management mechanism. Local install docs cover manual fallback paths.

---

## Separate Workstream / Drone Non-Regression

**Method:** Review of plugin artifacts and docs

**Findings:**
- No drone plugin files in artifacts.
- No drone skills exposed.
- No drone demos added.
- `plugin doctor` correctly detects the separate drone workstream and reports it without exposing controls.
- Plugin docs include the required separate-workstream note.
- `package-plugins.sh` excludes `*drone*` files.

**Result:** Pass — drone workstream is not modified or exposed by plugins.

---

## Build and Test Results

| Command | Result |
|---|---|
| `zig build` | Pass |
| `zig build test` | Pass |
| `./scripts/package-plugins.sh` | Pass |
| `./zig-out/bin/aegis plugin doctor codex` | Pass |
| `./zig-out/bin/aegis plugin doctor claude` | Pass |
| `./zig-out/bin/aegis plugin manifest codex` | Pass |
| `./zig-out/bin/aegis plugin manifest claude` | Pass |
| `./zig-out/bin/aegis plugin install codex --dry-run` | Pass |
| `./zig-out/bin/aegis plugin install claude --dry-run` | Pass |
| `cat tests/plugin-fixtures/codex/pre_tool_use_command_dangerous.json \| ./zig-out/bin/aegis hook codex PreToolUse` | Blocked (expected) |
| `cat tests/plugin-fixtures/claude/pre_tool_use_command_dangerous.json \| ./zig-out/bin/aegis hook claude PreToolUse` | Blocked (expected) |
| `./zig-out/bin/aegis redteam --ci` | 10/10 passed |
| `./zig-out/bin/aegis doctor` | Pass |

---

## Known Limitations

- Hooks are advisory; enforcement depends on host support.
- Official marketplace availability is not yet implemented.
- Plugin installation defaults to preview/dry-run.
- No telemetry is collected.
- The plugins do not protect sessions launched outside Aegis.
- These plugins do not add MCP server functionality or drone-specific plugin features.

---

## Are the Plugins Ready to Publish?

**Yes.**

All acceptance criteria are met:
- [x] `PLUGIN_RELEASE_NOTES.md` exists
- [x] `LAUNCH_PLUGINS.md` exists
- [x] `examples/plugin-demo/` exists
- [x] Plugin issue templates exist
- [x] Plugin triage docs exist
- [x] Post-launch patch checklist exists
- [x] Plugin release checklist exists
- [x] README links to plugin docs
- [x] Plugin packages build
- [x] Plugin checksums generate
- [x] Secret scan passes
- [x] Docs do not overclaim
- [x] No MCP behavior added
- [x] No `.mcp.json` added
- [x] No drone plugin behavior added
- [x] No drone demos added
- [x] Existing Aegis tests pass
- [x] Existing plugin tests pass
- [x] Redteam passes (10/10)
- [x] Drone workstream not exposed

---

## Files Changed

### Created
- `PLUGIN_RELEASE_NOTES.md`
- `LAUNCH_PLUGINS.md`
- `examples/plugin-demo/README.md`
- `examples/plugin-demo/codex-demo.md`
- `examples/plugin-demo/claude-demo.md`
- `examples/plugin-demo/fake-hook-payloads/README.md`
- `.github/ISSUE_TEMPLATE/codex_plugin_bug.md`
- `.github/ISSUE_TEMPLATE/claude_plugin_bug.md`
- `.github/ISSUE_TEMPLATE/aegis_cli_plugin_bug.md`
- `.github/ISSUE_TEMPLATE/plugin_security_bug.md`
- `.github/ISSUE_TEMPLATE/plugin_compatibility.md`
- `.github/ISSUE_TEMPLATE/plugin_docs_issue.md`
- `docs/integrations/plugin-triage.md`
- `docs/integrations/plugin-postlaunch-patch-checklist.md`
- `docs/integrations/plugin-release-checklist.md`
- `docs/integrations/p07-plugin-launch-and-postlaunch.md`

### Updated
- `README.md` — added Agent Host Plugins section

### Generated (not committed)
- `dist/plugins/aegis-codex-plugin-v1.1.0.zip`
- `dist/plugins/aegis-claude-code-plugin-v1.1.0.zip`
- `dist/plugins/aegis-claude-marketplace-v1.1.0.zip`
- `dist/plugins/aegis-plugin-checksums.txt`
