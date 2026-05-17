# Orca Repo Marketplace Readiness Audit

**Date:** 2026-05-10
**Auditor:** Automated marketplace readiness verification
**Version audited:** Orca 1.1.0

---

## Summary

This audit verifies that Orca is ready for public repo-marketplace installation through Codex and Claude Code.

**Result:** Ready pending one manual action (public repo rename/push).

All release-blocking issues found during this audit have been fixed. The codebase now uses consistent `orca` branding in plugin manifests, hooks, skills, docs, and tests. `zig build test` passes cleanly.

---

## Public Repository Status

| Check | Status | Notes |
|-------|--------|-------|
| Local git remote | `christopherkarani/Orca.git` | **BLOCKER:** Must be `chriskarani/orca` |
| GitHub repo exists | `chriskarani/orca` not found | **BLOCKER:** Repo must be created/renamed and pushed |
| Repo visibility | Unknown | Must be public |
| Default branch | Unknown | Must be correct |

**Required manual action:**
1. Rename the GitHub repository to `chriskarani/orca` (or create a new repo and push).
2. Update the local remote: `git remote set-url origin https://github.com/chriskarani/orca.git`
3. Ensure the repo is public.

---

## Root Marketplace Files

| File | Status | Validates | Points to |
|------|--------|-----------|-----------|
| `.agents/plugins/marketplace.json` | EXISTS | YES | `./integrations/codex-plugin` |
| `.claude-plugin/marketplace.json` | EXISTS | YES | `./integrations/claude-code-plugin` |

Both files use marketplace name `orca`.

---

## Codex Marketplace Status

| Check | Status | Notes |
|-------|--------|-------|
| `integrations/codex-plugin/.codex-plugin/plugin.json` | EXISTS, VALID | Name: `orca` |
| `integrations/codex-plugin/skills/` | EXISTS | 5 skills: `orca-doctor`, `orca-init`, `orca-protect`, `orca-redteam`, `orca-replay` |
| `integrations/codex-plugin/hooks/hooks.json` | EXISTS, VALID | Commands: `orca hook codex ...` |
| `integrations/codex-plugin/README.md` | EXISTS | Rebranded to Orca |
| No `.mcp.json` | CONFIRMED | None found |
| No drone skills | CONFIRMED | None found |
| No secrets | CONFIRMED | Clean |

**Fixed during audit:**
- Plugin manifest name changed from `orca` to `orca`
- Hooks changed from `orca hook codex` to `orca hook codex`
- Skill directories renamed from `orca-*` to `orca-*`
- README fully rebranded

---

## Claude Code Marketplace Status

| Check | Status | Notes |
|-------|--------|-------|
| `integrations/claude-code-plugin/.claude-plugin/plugin.json` | EXISTS, VALID | Name: `orca` |
| `integrations/claude-code-plugin/skills/` | EXISTS | 5 skills: `doctor`, `init`, `protect`, `redteam`, `replay` |
| `integrations/claude-code-plugin/hooks/hooks.json` | EXISTS, VALID | Commands: `orca hook claude ...` |
| `integrations/claude-code-plugin/README.md` | EXISTS | Rebranded to Orca |
| No `.mcp.json` | CONFIRMED | None found |
| No drone skills | CONFIRMED | None found |
| No secrets | CONFIRMED | Clean |

**Fixed during audit:**
- Plugin manifest name changed from `orca` to `orca`
- Hooks changed from `orca hook claude` to `orca hook claude`
- README fully rebranded
- Skill files updated from `orca` to `orca`

---

## Plugin Manifest Status

| Host | Manifest Path | Name | Display Name | Status |
|------|--------------|------|--------------|--------|
| Codex | `integrations/codex-plugin/.codex-plugin/plugin.json` | `orca` | `Orca` | VALID |
| Claude | `integrations/claude-code-plugin/.claude-plugin/plugin.json` | `orca` | `Orca` | VALID |

---

## Plugin Doctor Status

| Command | Result |
|---------|--------|
| `orca plugin doctor codex` | PASS — detects marketplace file, manifest, plugin directory, host binary |
| `orca plugin doctor claude` | PASS — detects marketplace file, manifest, plugin directory, host binary |

---

## Plugin Install Dry-Run Status

| Command | Result |
|---------|--------|
| `orca plugin install codex --dry-run` | PASS — dry-run, no mutations, points to manual install |
| `orca plugin install claude --dry-run` | PASS — dry-run, no mutations, points to manual install |

---

## Packaging Status

| Artifact | Status |
|----------|--------|
| `dist/plugins/orca-codex-plugin-v1.1.0.zip` | BUILT |
| `dist/plugins/orca-claude-code-plugin-v1.1.0.zip` | BUILT |
| `dist/plugins/orca-opencode-plugin-v1.1.0.zip` | BUILT |
| `dist/plugins/orca-plugin-checksums.txt` | BUILT |

Package contents verified:
- No `.mcp.json` files
- No drone files
- No planning files
- No temporary files
- No real secrets

---

## Hook Smoke Tests

| Host | Fixture | Result |
|------|---------|--------|
| Codex | `pre_tool_use_command_dangerous.json` | PASS — blocked with valid JSON decision |
| Claude | `pre_tool_use_command_dangerous.json` | PASS — blocked with valid JSON decision |

No fake secrets leaked. stdout is valid JSON.

---

## Public Install Docs Status

| Doc | Codex Command | Claude Command | Limitation Language |
|-----|---------------|----------------|---------------------|
| `README.md` | `codex plugin marketplace add chriskarani/orca` | `claude plugin marketplace add chriskarani/orca` | YES |
| `docs/integrations/codex.md` | `codex plugin marketplace add chriskarani/orca` | — | YES |
| `docs/integrations/claude-code.md` | — | `claude plugin marketplace add chriskarani/orca` | YES |
| `docs/integrations/repo-marketplace-install.md` | `codex plugin marketplace add chriskarani/orca` | `claude plugin marketplace add chriskarani/orca` | YES |

**Fixed during audit:**
- `YOUR_ORG/orca` placeholders replaced with `chriskarani/orca`
- Artifact names updated from `orca-*` to `orca-*`
- Binary paths updated from `./zig-out/bin/orca` to `./zig-out/bin/orca`
- Commands updated from `orca *` to `orca *`

---

## README Review

`README.md` includes:
- Orca product name
- Quick start
- Codex plugin install command
- Claude Code plugin install command
- OpenCode install status
- Plugin security model
- Limitations (including no MCP, no drone features)
- Release/install docs links
- The strongest local protection warning

---

## Secret Scan Result

| Scan | Result |
|------|--------|
| Real secrets in public docs/manifests | NONE FOUND |
| Fake secrets in test fixtures | Expected (`fake_p05_secret_value`) — acceptable |
| Private keys | NONE FOUND |
| API keys with values | NONE FOUND |

---

## Unsupported Claim Scan Result

| Phrase | Found As | Status |
|--------|----------|--------|
| "official marketplace" | Limitation only | ACCEPTABLE |
| "MCP server behavior" | Limitation only | ACCEPTABLE |
| "drone-specific plugin" | Limitation only | ACCEPTABLE |
| "perfect sandbox" | Limitation only | ACCEPTABLE |
| "universal transparent" | Limitation only | ACCEPTABLE |

No unsupported claims found in public-facing docs.

---

## Live Install Validation

Not attempted. The public repo `chriskarani/orca` does not yet exist.

Once the repo is public, the following commands should be tested:

```bash
codex plugin marketplace add chriskarani/orca
```

```bash
claude plugin marketplace add chriskarani/orca
claude plugin install orca@orca --scope user
```

---

## Blockers Found

| Blocker | Severity | Fixed | Notes |
|---------|----------|-------|-------|
| Git remote points to `christopherkarani/Orca.git` | HIGH | NO | Requires manual repo rename/push |
| GitHub repo `chriskarani/orca` does not exist | HIGH | NO | Requires manual creation |
| Codex plugin manifest name was `orca` | HIGH | YES | Changed to `orca` |
| Claude plugin manifest name was `orca` | HIGH | YES | Changed to `orca` |
| Codex hooks called `orca hook codex` | HIGH | YES | Changed to `orca hook codex` |
| Claude hooks called `orca hook claude` | HIGH | YES | Changed to `orca hook claude` |
| Docs used `YOUR_ORG/orca` placeholder | HIGH | YES | Changed to `chriskarani/orca` |
| Docs referenced `orca-*` artifact names | MEDIUM | YES | Changed to `orca-*` |
| Docs referenced `./zig-out/bin/orca` | MEDIUM | YES | Changed to `./zig-out/bin/orca` |
| Codex skills used `orca-*` naming | MEDIUM | YES | Renamed to `orca-*` |
| Test expected `edge` in build scripts | MEDIUM | YES | Updated test and ps1 script |
| Test expected `orca run --` in docs | MEDIUM | YES | Updated tests |
| `orca-plugin.md` filename | LOW | YES | Renamed to `orca-cli-plugin.md` |

---

## Tests Run

```bash
zig build        # PASS
zig build test   # PASS (560 tests; 0 failures)
```

All tests pass after fixes.

---

## Files Changed

### Plugin manifests
- `integrations/codex-plugin/.codex-plugin/plugin.json`
- `integrations/claude-code-plugin/.claude-plugin/plugin.json`

### Hooks
- `integrations/codex-plugin/hooks/hooks.json`
- `integrations/claude-code-plugin/hooks/hooks.json`

### Codex plugin skills (renamed + updated)
- `integrations/codex-plugin/skills/orca-doctor/SKILL.md` (was `orca-doctor`)
- `integrations/codex-plugin/skills/orca-init/SKILL.md` (was `orca-init`)
- `integrations/codex-plugin/skills/orca-protect/SKILL.md` (was `orca-protect`)
- `integrations/codex-plugin/skills/orca-redteam/SKILL.md` (was `orca-redteam`)
- `integrations/codex-plugin/skills/orca-replay/SKILL.md` (was `orca-replay`)

### Claude plugin skills (updated)
- `integrations/claude-code-plugin/skills/doctor/SKILL.md`
- `integrations/claude-code-plugin/skills/init/SKILL.md`
- `integrations/claude-code-plugin/skills/protect/SKILL.md`
- `integrations/claude-code-plugin/skills/redteam/SKILL.md`
- `integrations/claude-code-plugin/skills/replay/SKILL.md`

### Plugin READMEs
- `integrations/codex-plugin/README.md`
- `integrations/claude-code-plugin/README.md`

### Docs
- `README.md`
- `docs/integrations/codex.md`
- `docs/integrations/claude-code.md`
- `docs/integrations/repo-marketplace-install.md`
- `docs/integrations/orca-cli-plugin.md` (renamed from `orca-plugin.md`)

### Example marketplace files
- `integrations/codex-plugin/examples/marketplace.json`
- `integrations/claude-marketplace/.claude-plugin/marketplace.json`
- `integrations/claude-marketplace/README.md`

### Tests
- `tests/phase25_cli_hardening.zig`
- `tests/phase36_codex_plugin.zig`
- `tests/phase37_claude_plugin.zig`
- `tests/phase38_plugin_security_and_compatibility.zig`

### Build scripts
- `scripts/build-release.ps1`

---

## Marketplace Readiness Result

### Is `codex plugin marketplace add chriskarani/orca` ready?

**YES — pending public repo availability.**

All Codex plugin files, marketplace configuration, docs, and tests are ready. The only remaining requirement is that the public GitHub repository `chriskarani/orca` exists and is public.

### Is `claude plugin marketplace add chriskarani/orca` ready?

**YES — pending public repo availability.**

All Claude Code plugin files, marketplace configuration, docs, and tests are ready. The only remaining requirement is that the public GitHub repository `chriskarani/orca` exists and is public.

---

## Final Acceptance Criteria

| Criterion | Status |
|-----------|--------|
| `.agents/plugins/marketplace.json` exists and validates | PASS |
| `.claude-plugin/marketplace.json` exists and validates | PASS |
| Codex marketplace points to `./integrations/codex-plugin` | PASS |
| Claude marketplace points to `./integrations/claude-code-plugin` | PASS |
| Codex plugin files exist and validate | PASS |
| Claude plugin files exist and validate | PASS |
| Public docs include correct install commands | PASS |
| Docs distinguish repo marketplace from official marketplace | PASS |
| `orca plugin doctor codex` works | PASS |
| `orca plugin doctor claude` works | PASS |
| `orca plugin manifest codex` works | PASS |
| `orca plugin manifest claude` works | PASS |
| `orca plugin install codex --dry-run` works | PASS |
| `orca plugin install claude --dry-run` works | PASS |
| Plugin packages build | PASS |
| No secrets introduced | PASS |
| No MCP behavior added | PASS |
| No drone plugin behavior added | PASS |
| Audit doc exists | PASS |
| `zig build test` passes | PASS |

---

## Next Steps

1. **Create/rename the public GitHub repository to `chriskarani/orca`.**
2. **Push the current branch to the public repo.**
3. **Verify repo is public.**
4. **Test live install commands** (optional but recommended):
   ```bash
   codex plugin marketplace add chriskarani/orca
   claude plugin marketplace add chriskarani/orca
   claude plugin install orca@orca --scope user
   ```
5. **Tag a release** (e.g., `v1.1.0`) so marketplace references resolve to a stable version.
