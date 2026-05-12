# P06 — Plugin Distribution and Marketplace

> Phase: P06
> Date: 2026-05-09
> Status: Complete

---

## Summary

Packaged and distributed the Aegis Codex and Claude Code plugins. Created packaging scripts, generated checksums, updated install docs, added marketplace catalog, updated release workflow, created compatibility matrix, and ran secret scans. All verification commands pass.

---

## Files Added

### Packaging scripts

```text
scripts/package-plugins.sh
scripts/package-plugins.ps1
```

### Documentation

```text
docs/integrations/plugin-troubleshooting.md
docs/integrations/plugin-compatibility.md
docs/integrations/separate-workstream-guardrails.md
PLUGIN_CHANGELOG.md
```

### Plugin artifacts (generated)

```text
dist/plugins/aegis-codex-plugin-v1.1.0.zip
dist/plugins/aegis-claude-code-plugin-v1.1.0.zip
dist/plugins/aegis-claude-marketplace-v1.1.0.zip
dist/plugins/aegis-plugin-checksums.txt
```

---

## Files Modified

### Documentation updates

```text
docs/integrations/codex.md
  - Added distribution/install section with release artifact install
  - Added local path install
  - Added local marketplace install
  - Added manual fallback install
  - Added verify commands (doctor, manifest, hook smoke test, redteam)
  - Added uninstall instructions
  - Added troubleshooting section
  - Added known limitations

docs/integrations/claude-code.md
  - Added distribution/install section with release artifact install
  - Added local path install
  - Added local marketplace install
  - Added manual fallback install
  - Added verify commands (doctor, manifest, hook smoke test, redteam)
  - Added uninstall instructions
  - Added troubleshooting section
  - Added known limitations

docs/integrations/orca-cli-plugin.md
  - Added plugin packaging section
  - Added install dry-run behavior section
  - Added host limitations section
  - Added no telemetry / no SaaS statement
  - Added compatibility section
  - Removed MCP server behavior claims (now documented as stub only)

docs/integrations/plugin-security-model.md
  - Updated to reflect P06 scope
  - Added "What Plugins Do Not Do" section
  - Added explicit statements: no MCP, no drone, no telemetry, no SaaS
  - Added strongest protection warning
```

### Workflow updates

```text
.github/workflows/release.yml
  - Added plugin packaging step
  - Added plugin artifact verification step
  - Added secret scan over plugin artifacts step
  - Added plugin artifacts to upload path
```

---

## Packaging Scripts Added

### scripts/package-plugins.sh

- Packages Codex plugin into `dist/plugins/aegis-codex-plugin-vX.Y.Z.zip`
- Packages Claude Code plugin into `dist/plugins/aegis-claude-code-plugin-vX.Y.Z.zip`
- Packages Claude marketplace into `dist/plugins/aegis-claude-marketplace-vX.Y.Z.zip`
- Generates SHA-256 checksums in `dist/plugins/aegis-plugin-checksums.txt`
- Secret-scans artifacts before completing
- Excludes `.mcp.json`, drone files, build artifacts, temp files, secrets

**Environment variables:**
- `AEGIS_PLUGIN_VERSION` — plugin artifact version (defaults to `AEGIS_VERSION` or `1.1.0`)
- `AEGIS_DIST_DIR` — output directory (defaults to `dist/plugins`)

### scripts/package-plugins.ps1

- PowerShell equivalent for Windows
- Same functionality as the shell script
- Uses `[System.IO.Compression.ZipFile]` for archive operations
- Supports same environment variables as the shell script

---

## Artifacts Generated

```bash
$ ls -la dist/plugins/
-rw-r--r--@ 1 user  staff  8000  May 9 11:04 aegis-claude-code-plugin-v1.1.0.zip
-rw-r--r--@ 1 user  staff  1145  May 9 11:04 aegis-claude-marketplace-v1.1.0.zip
-rw-r--r--@ 1 user  staff  7972  May 9 11:04 aegis-codex-plugin-v1.1.0.zip
-rw-r--r--@ 1 user  staff   300  May 9 11:04 aegis-plugin-checksums.txt
```

Checksums:
```
57e0e44e91589376880fc56ff2319b4f2a4babec29bee58f36503312f91aa17f  aegis-claude-code-plugin-v1.1.0.zip
5e056e7211b822a990cffb42b3e0367c3161e133bbdb5c45d7d9c4ccff921a42  aegis-claude-marketplace-v1.1.0.zip
d9a4fbb99d3ccc22aaabc08ee1506102aa5200636d038cbf3bfe483eb8b338a2  aegis-codex-plugin-v1.1.0.zip
```

---

## Install Docs Updated

### Codex install docs (`docs/integrations/codex.md`)

Covers:
- Prerequisites
- Build from source
- Install from release artifact
- Install from local path
- Local marketplace install
- Manual fallback install
- Verify with `aegis plugin doctor codex`
- Verify manifest with `aegis plugin manifest codex`
- Verify hooks with fake payload test
- Run `aegis redteam --ci`
- Uninstall instructions
- Troubleshooting
- Known limitations

Does not claim official Codex marketplace availability.

### Claude Code install docs (`docs/integrations/claude-code.md`)

Covers:
- Prerequisites
- Build from source
- Install from release artifact
- Install from local path
- Local marketplace install
- Manual fallback install
- Verify with `aegis plugin doctor claude`
- Verify manifest with `aegis plugin manifest claude`
- Verify hooks with fake payload test
- Run `aegis redteam --ci`
- Uninstall instructions
- Troubleshooting
- Known limitations

States: "This repository includes a local Claude Code marketplace catalog for installing the Aegis plugin. It is not an official marketplace approval unless explicitly stated in release notes."

### Aegis CLI plugin docs (`docs/integrations/orca-cli-plugin.md`)

Covers:
- Plugin surface commands (`plugin doctor`, `plugin manifest`, `plugin install`, `decide`, `hook`)
- Plugin packaging relationship
- Install dry-run behavior
- Host limitations
- No telemetry
- No SaaS requirement
- Strongest protection remains `aegis run`

---

## Marketplace Status

- Claude marketplace catalog exists at `integrations/claude-marketplace/.claude-plugin/marketplace.json`
- Codex marketplace example exists at `integrations/codex-plugin/examples/marketplace.json`
- Both are documented as example catalogs only
- Official marketplace availability is not claimed
- Release artifacts include marketplace zip for local distribution

---

## Release Workflow Status

Updated `.github/workflows/release.yml`:

- Runs `zig build test`
- Runs red-team CI
- Builds release artifacts
- Packages plugins
- Verifies plugin artifacts
- Secret-scans plugin artifacts
- Uploads plugin artifacts alongside release binaries

No secrets are printed in workflows.
No external network access is required beyond normal CI checkout.

---

## Compatibility Matrix

Created `docs/integrations/plugin-compatibility.md` with:

| Feature | Aegis CLI | Codex Plugin | Claude Code Plugin |
|---|---|---|---|
| plugin doctor | yes | calls CLI | calls CLI |
| manifest status | yes | yes | yes |
| install dry-run | yes | yes | yes |
| skills | n/a | yes | yes |
| hooks | n/a | yes | yes |
| decision API | yes | calls CLI | calls CLI |
| MCP server behavior | no | no | no |
| drone plugin features | no | no | no |
| telemetry | no | no | no |

Also includes host limitation notes and version compatibility.

---

## Secret Scan Result

### Scopes scanned

- `integrations/codex-plugin/` — Clean
- `integrations/claude-code-plugin/` — Clean
- `integrations/claude-marketplace/` — Clean
- `docs/integrations/` — Clean
- `dist/plugins/` — Clean
- `scripts/package-plugins.sh` — Clean
- `scripts/package-plugins.ps1` — Clean
- `.github/workflows/release.yml` — Clean
- `PLUGIN_CHANGELOG.md` — Clean

### Scan method

- Automated secret scan in packaging scripts
- Manual grep for secret-like patterns
- No fake secrets leaked outside fixtures
- No real secrets found

---

## Tests Run

### Build and test

```bash
zig build        → Pass
zig build test   → Pass (0 failures)
```

### Plugin commands

```bash
./zig-out/bin/aegis plugin doctor codex        → plugin directory: present ✓
./zig-out/bin/aegis plugin doctor claude       → plugin directory: present ✓
./zig-out/bin/aegis plugin manifest codex      → manifest: exists ✓
./zig-out/bin/aegis plugin manifest claude     → manifest: exists ✓
./zig-out/bin/aegis plugin install codex --dry-run    → dry-run works ✓
./zig-out/bin/aegis plugin install claude --dry-run   → dry-run works ✓
```

### Hook smoke tests

```bash
cat tests/plugin-fixtures/codex/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook codex PreToolUse    → allow ✓
cat tests/plugin-fixtures/claude/pre_tool_use_command_safe.json \
  | ./zig-out/bin/aegis hook claude PreToolUse   → allow ✓
```

### Redteam and doctor

```bash
./zig-out/bin/aegis redteam --ci    → 10/10 fixtures passed, 100% ✓
./zig-out/bin/aegis doctor           → All capability checks report honestly ✓
```

### Packaging

```bash
./scripts/package-plugins.sh    → Success ✓
ls -la dist/plugins             → 4 files generated ✓
cat dist/plugins/aegis-plugin-checksums.txt → 3 checksums ✓
```

---

## Separate Workstream / Drone Non-Regression Result

- No drone files in plugin packages ✓
- No drone skills in plugins ✓
- No drone demos in plugin docs ✓
- No operational drone-control instructions ✓
- Existing drone tests not modified ✓
- Plugin docs reference separate workstream only to state it is out of scope ✓

---

## Known Limitations

1. **Policy not present**: `.aegis/policy.yaml` is missing in the test workspace. Hooks and decide still function using built-in default policy.
2. **Host plugin loading**: Actual Codex/Claude Code plugin installation depends on host version and is not tested here.
3. **Marketplace**: Official marketplace availability is not yet implemented; only local example catalogs exist.
4. **Plugin install**: `aegis plugin install` is dry-run/preview only; actual host plugin installation requires manual integration.
5. **No MCP behavior**: This plugin plan does not add MCP server behavior.
6. **No drone features**: This plugin plan does not add drone-specific plugin features.

---

## Whether P07 Is Safe to Start

**Yes. P07 (Plugin Launch and Postlaunch) is safe to start.**

All acceptance criteria are met:

- [x] Plugin packages generated
- [x] Plugin checksums generated
- [x] Codex install docs exist
- [x] Claude install docs exist
- [x] Aegis CLI plugin docs exist
- [x] Plugin troubleshooting docs exist
- [x] Plugin compatibility matrix exists
- [x] Plugin release notes/changelog exists
- [x] Release workflow includes plugin artifacts
- [x] No secrets in artifacts
- [x] No MCP behavior was added
- [x] No `.mcp.json` was added
- [x] No drone plugin behavior was added
- [x] No drone files in plugin packages
- [x] Existing Aegis tests pass
- [x] Existing plugin security tests pass
- [x] Existing drone tests pass or safe skip reasons are documented
- [x] Separate workstream guardrails documented

---

*End of P06 handoff.*
