# Orca Launch Operations Report

Generated: 2026-05-10

---

## GitHub Release Status

Current as of 2026-05-17: this report is historical launch-operations evidence, not a
current production-readiness pass. Re-run the release verifier against freshly built
artifacts before using this release for installation guidance.

- **Release URL**: https://github.com/christopherkarani/Orca/releases/tag/v1.1.0
- **Title**: "Orca v1.1.0 — Runtime guardrails and plugins for AI agents"
- **Tag**: `v1.1.0`
- **Draft**: No
- **Prerelease**: No
- **Orca-branded**: Yes
- **Security limitations included**: Yes
- **Install/verify steps included**: Yes

### Artifacts Verified
- [x] `orca-v1.1.0-darwin-amd64.tar.gz`
- [x] `orca-v1.1.0-darwin-arm64.tar.gz`
- [ ] `orca-v1.1.0-linux-amd64.tar.gz`
- [ ] `orca-v1.1.0-linux-arm64.tar.gz`
- [x] `orca-v1.1.0-windows-amd64.zip`
- [x] `orca-codex-plugin-v1.1.0.zip`
- [x] `orca-claude-code-plugin-v1.1.0.zip`
- [x] `orca-plugin-checksums.txt`
- [ ] `checksums.txt`

### Issues Found
- The published release is missing Linux Orca archives required by the release checklist.
- The published `checksums.txt` must be regenerated from the final Orca artifact names before package-manager manifests are published.

---

## Repo Metadata Status

- **Repo**: https://github.com/christopherkarani/Orca
- **Description**: Updated to "Local runtime guardrails and plugins for AI agents."
- **Topics**: Updated to `ai-agents`, `agent-security`, `developer-tools`, `codex`, `claude-code`, `zig`, `security`, `runtime`, `plugins`, `redteam`
- **Name**: "Orca" (unchanged; renaming the repository itself is a destructive operation left for manual decision)

### Action Taken
- `gh repo edit --description "Local runtime guardrails and plugins for AI agents."` — applied successfully
- `gh repo edit --add-topic "ai-agents,agent-security,developer-tools,codex,claude-code,zig,security,runtime,plugins,redteam"` — applied successfully

---

## Label Creation Status

### Labels Already Existed
- `bug`
- `documentation`
- `duplicate`
- `enhancement`
- `good first issue`
- `help wanted`
- `invalid`
- `question`
- `wontfix`

### Labels Created
- `release` (#fc6d26)
- `security` (#b60205)
- `plugin:codex` (#0052cc)
- `plugin:claude` (#0052cc)
- `plugin:cli` (#0e8a16)
- `plugin:hooks` (#0e8a16)
- `plugin:install` (#d93f0b)
- `plugin:compatibility` (#d93f0b)
- `plugin:docs` (#1d76db)
- `plugin:packaging` (#1d76db)
- `regression` (#b60205)
- `good-first-issue` (#7057ff)

### Action Taken
- All missing labels created via `gh label create` with `--force` flag.
- No existing labels were deleted or modified.

---

## Launch Post Docs Status

- **File**: `docs/release/orca-launch-posts.md`
- **Status**: Created
- **Platforms covered**:
  - GitHub release announcement
  - Hacker News
  - Reddit
  - X / LinkedIn
  - DevTools / Security community post
- **Required sentence included in all posts**: Yes
- **Forbidden claims avoided**: Yes

---

## 72-Hour Watch Doc Status

- **File**: `docs/release/orca-72-hour-watch.md`
- **Status**: Created
- **Contents**:
  - Hourly checklists (0–6, 6–24, 24–72)
  - GitHub issue query examples
  - Release comment monitoring guide
  - Install/plugin failure signs table
  - P0/P1/P2/P3 triage definitions
  - Patch release criteria
  - Patch branch naming convention
  - Patch release checklist
  - Monitoring schedule

---

## Public User Flow Status

Verified from clean checkout on macOS:

| Step | Command | Status |
|---|---|---|
| Build | `zig build` | PASS |
| Doctor | `./zig-out/bin/orca doctor` | PASS |
| Plugin doctor (Codex) | `./zig-out/bin/orca plugin doctor codex` | PASS |
| Plugin doctor (Claude) | `./zig-out/bin/orca plugin doctor claude` | PASS |
| Package plugins | `./scripts/package-plugins.sh` | PASS |

### README Flow Assessment
A brand-new user can follow README instructions without needing internal planning docs:
- `zig build` is the first step and it works.
- `./zig-out/bin/orca doctor` confirms installation.
- `./zig-out/bin/orca init --preset generic-agent` is documented for policy setup.
- Plugin installation paths are documented per host.
- Checksum verification steps are included.
- Troubleshooting docs are linked.

### Notes
- `.orca/policy.yaml` is missing until `orca init` is run. This is expected and documented.
- No local sessions detected. This is expected on a fresh checkout.

---

## Files Changed

- `docs/release/orca-launch-posts.md` (created)
- `docs/release/orca-72-hour-watch.md` (created)
- `docs/release/orca-launch-ops-report.md` (created)

---

## Missing Manual Actions

1. **Repository rename**: The repository is still named "Orca". Renaming to "Orca" or "orca" is a manual decision that affects all URLs, clones, and forks. If renamed, update:
   - All internal documentation links
   - Release URLs in launch posts
   - README badges or shields
   - Package manager manifests (if any)

2. **Social media posting**: Launch post copy is prepared but not published. Post manually to:
   - Hacker News
   - Reddit (relevant subreddits)
   - X / LinkedIn
   - DevTools / security communities

3. **Community monitoring**: The 72-hour watch doc is prepared but monitoring must be performed manually by the launch owner.

4. **Release asset repair**: Publish the missing Linux Orca archives and regenerate `checksums.txt` from the final Orca artifact names before promoting this release through package managers.

5. **Release checksum cross-check**: Download release artifacts and verify them from a clean machine after the asset repair.

---

## Launch Operations Complete?

| Task | Status |
|---|---|
| GitHub CLI access verified | Yes |
| Release page verified | Blocked: missing Linux Orca archives and current checksum drift |
| Repo metadata updated | Yes |
| GitHub labels created | Yes |
| Launch posts prepared | Yes |
| 72-hour watch doc prepared | Yes |
| Public user flow verified | Yes |
| Final report created | Historical only |

**Launch operations are HISTORICAL.** The current published asset set must pass
`scripts/verify-release.sh` before the release is treated as production-ready.
