# Orca 72-Hour Launch Watch

Post-release monitoring checklist for the first 72 hours after the Orca v1.1.0 launch.

---

## Check Every Few Hours

### Hour 0–6 (Immediate)
- [ ] GitHub release page loads correctly: https://github.com/christopherkarani/Aegis/releases/tag/v1.1.0
- [ ] All release assets are downloadable (no 404s)
- [ ] Checksum file (`orca-plugin-checksums.txt`) is present and valid
- [ ] No critical issues filed in the first 30 minutes
- [ ] No CI failures on the default branch

### Hour 6–24 (First Day)
- [ ] Review new GitHub issues for `bug`, `security`, or `regression` labels
- [ ] Check release page comments for install failures or confusion
- [ ] Monitor social posts (HN, Reddit, X, LinkedIn) for corrections or questions
- [ ] Verify no secrets leaked in issue templates or comments
- [ ] Check that `zig build` still works from a clean checkout

### Day 2–3 (Stabilization)
- [ ] Triage all open issues filed since release
- [ ] Check for patterns in plugin install failures
- [ ] Verify no P0 or P1 issues remain unassigned
- [ ] Prepare patch branch if needed (see below)

---

## GitHub Issue Query Examples

### All issues filed since release
```
is:issue created:>2026-05-09
```

### Potential regressions
```
is:issue label:regression
```

### Security concerns
```
is:issue label:security
```

### Plugin-specific issues
```
is:issue label:plugin:codex
is:issue label:plugin:claude
is:issue label:plugin:install
is:issue label:plugin:compatibility
```

### Bugs only
```
is:issue label:bug
```

### Good first issues (for community onboarding)
```
is:issue label:good-first-issue
```

---

## Release Comments to Monitor

Watch the release page for:
- "Download failed" or "404" reports
- Checksum mismatch reports
- "How do I install this?" confusion
- Claims that Orca is a SaaS/telemetry product (correct gently)
- Requests for unsupported features (MCP server, drone plugins, marketplace)
- Security concerns or vulnerability reports (escalate immediately)

---

## Install / Plugin Failure Signs

Watch for these patterns in issues and comments:

| Sign | Likely Cause | Action |
|---|---|---|
| "checksum failed" | Corrupt download or wrong file | Ask user to re-download, verify file size |
| "plugin not detected" | Wrong plugin path or host version | Point to troubleshooting docs |
| "orca command not found" | PATH issue or build failure | Ask for `zig build` output |
| "hooks not firing" | Host does not support hooks | Document limitation, no code change |
| "policy.yaml missing" | User skipped `orca init` | Point to quickstart |
| "Codex/Claude not found" | Host not installed or not in PATH | Expected behavior; document |

---

## Triage Definitions

### P0 — Critical
- Security vulnerability in released artifacts
- Build broken on supported platforms
- Plugin artifacts corrupt or missing from release
- Data loss or corruption in audit logs

**Action:** Immediate patch release (`v1.0.1` or `v1.1.1`). Notify users via release comments.

### P1 — High
- Install flow broken for major platforms
- `orca doctor` crashes or reports false negatives
- Plugin hooks silently fail
- Checksum verification fails for legitimate downloads

**Action:** Target patch release within 24–48 hours. Create `patch/` branch immediately.

### P2 — Medium
- Documentation unclear or misleading
- Minor UI/UX issues in CLI output
- Platform-specific warnings that do not block usage
- Feature requests that align with roadmap

**Action:** Schedule for next minor release or patch if capacity allows.

### P3 — Low
- Typos in docs
- Cosmetic output issues
- Feature requests outside current scope
- Questions answered by existing docs

**Action:** Label `good-first-issue` or close with docs reference.

---

## When to Cut a Patch Release

Cut a patch release (`v1.1.1`) when:
1. A P0 issue is confirmed and fixed.
2. A P1 issue affects multiple users and a fix is ready.
3. A critical documentation fix prevents successful installation.

Do not cut a patch for:
- Single-user platform-specific issues
- Feature requests
- Cosmetic changes
- Documentation improvements that do not block install

---

## Patch Branch Naming

Format: `patch/v{MAJOR}.{MINOR}.{PATCH}`

Examples:
- `patch/v1.1.1`
- `patch/v1.1.2`

---

## Patch Release Checklist

1. Create patch branch from the release tag:
   ```sh
   git checkout -b patch/v1.1.1 v1.1.0
   ```
2. Cherry-pick or apply the fix.
3. Update version strings (if any hardcoded).
4. Run full verification:
   ```sh
   zig build
   zig build test
   ./zig-out/bin/orca redteam --ci
   ./zig-out/bin/orca plugin doctor codex
   ./zig-out/bin/orca plugin doctor claude
   ./scripts/package-plugins.sh
   ```
5. Update `PLUGIN_RELEASE_NOTES.md` with patch notes.
6. Tag:
   ```sh
   git tag -a v1.1.1 -m "Orca v1.1.1"
   git push origin patch/v1.1.1 --tags
   ```
7. Create GitHub release from the new tag.
8. Upload artifacts and checksums.
9. Update release page with patch notes and cross-reference to original release.
10. Monitor for 24 hours.

---

## Emergency Contacts / Escalation

- Security issues: Follow SECURITY.md process (private disclosure)
- Critical build failures: Tag maintainer in issue, do not post details publicly until triaged
- Social media corrections: Respond quickly with factual correction and link to docs

---

## Monitoring Schedule

| Timeframe | Check | Owner |
|---|---|---|
| T+0h | Release page, assets, first issues | Launch owner |
| T+2h | Issue triage, social replies | Launch owner |
| T+6h | Issue backlog, patterns | Launch owner |
| T+12h | Overnight issues, social mentions | Launch owner |
| T+24h | Full triage, patch decision | Launch owner |
| T+48h | Stabilization check, patch if needed | Launch owner |
| T+72h | Final review, close watch | Launch owner |
