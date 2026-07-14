# Zig Codebase: Improvement & Hardening Plan

**Date:** 2026-07-14  
**Scope:** Zig-side only (`src/`, packages under Zig CLI, related tests).  
**Out of scope:** Porting pack/regex evaluation from `orca-rs` into Zig; shipping a separate dcg product.  
**Status:** Draft plan for prioritization and phased execution.

---

## 1. North star

**Harden Zig as the trusted control plane:**

- Every **shell** decision fails closed through the Rust daemon (`Evaluate` / `shell_eval`).
- Every **non-shell** decision is validated Zig policy (files, env, network, MCP).
- Every **output** is redacted at presentation boundaries.
- Every **local server** (dashboard) is allowlisted and bind-safe.
- **Tests prove** behavior when the daemon dies, JSON is hostile, or secrets appear in events.

Tagline: *Zig owns orchestration and non-shell policy; orca-rs owns the shell pack engine. Do not blur those roles.*

---

## 2. Context and invariants

| Invariant | Rule |
|-----------|------|
| User-facing CLI | Zig `orca` only |
| Shell evaluation | Rust daemon only; **no Zig-native shell fallback** |
| Daemon unavailable | Fail-closed **deny** for shell |
| Build systems | Zig and Cargo stay separate; no `cargo` from `zig build` |
| Branding | Orca / `orca-daemon` — not dcg as a product |
| Secrets | Never persist raw secrets in logs, fixtures, reports, snapshots |

**Primary trees:**

```
src/cli/          # CLI, hooks, daemon client, plugins, status, doctor
src/policy/       # YAML policy load/validate/evaluate
src/intercept/    # run/shim env, approvals, command classifiers
src/audit/        # events, hash chain, redaction, replay
src/sandbox/      # OS backends
src/mcp/          # stdio MCP proxy
src/dashboard/    # local ops UI
tests/            # phase* integration matrices, fuzz
```

**Related product phases (do not block this plan):** P0–P2 UX (status, packs, modes, Pi, dashboard actions). Hardening work can ship in parallel as long as it does not regress product UX.

---

## 3. Priority overview

| Priority | Theme | Why |
|----------|--------|-----|
| **P0** | Control-plane integrity | Wrong allow/deny destroys the product |
| **P1** | Secrets & presentation | Leakage is unrecoverable trust loss |
| **P2** | Daemon IPC | DoS, races, path trust |
| **P3** | Policy bypass resistance | Matcher/validate gaps |
| **P4** | Runtime (env, sandbox, network, staging) | Blast radius of `orca run` |
| **P5** | MCP + dashboard | Local attack surface |
| **P6** | Plugins/install | “Protected” false claims |
| **P7** | Memory/Zig hygiene | Reliability under stress |
| **P8** | Test automation | Forces all of the above |
| **P9** | Structure | Maintainability (after safety) |

---

## 4. Workstreams (detailed)

### 4.1 Control-plane integrity (highest)

**Goal:** Decisions and “protected” claims stay true under failure and attack.

| Item | Description | Key paths |
|------|-------------|-----------|
| Fail-closed matrix | Every shell path: daemon down / timeout / protocol mismatch / bad JSON → **deny** | `shell_eval.zig`, `hook.zig`, `run.zig`, `shim.zig`, host adapters |
| No Zig shell fallback | Grep + tests: no branch uses Zig command rules as soft allow for shell | CLI + intercept |
| Host adapters | Unparseable payload, wrong event, missing command → documented fail-closed or explicit fail-open with tests | `hook.zig`, `agent_hook.zig`, plugins |
| Mode × severity | Single shared mapper; table tests so observe ≠ strict, ci never soft | Post-P2b; `shell_eval.zig` |
| Status/doctor honesty | Must not claim protected when daemon/smoke failed | `status.zig`, `doctor.zig`, `host_status.zig` |

**Acceptance:**

- [ ] Automated matrix: daemon unavailable → deny for `hook` / `run` shell / shim
- [ ] Automated matrix: protocol mismatch / malformed response → deny
- [ ] CI grep or test fails if shell allow without daemon Evaluate
- [ ] Status/doctor copy reviewed against real state enums

---

### 4.2 Daemon IPC

**Goal:** Client side of UDS is robust against races, abuse, and misconfiguration.

| Item | Description | Key paths |
|------|-------------|-----------|
| Strict NDJSON parse | Reject oversized lines; clear errors | `daemon.zig`, `daemon_contracts.zig` |
| Hostile frames | Truncated lines, garbage, slow hang → timeout | `daemon.zig` |
| Spawn/race | Stale socket, dead pid, double-start under lock | `daemon.zig` ensure path |
| Path trust | `ORCA_DAEMON` / binary resolve: refuse world-writable paths; doctor warns | `daemon.zig`, `doctor.zig` |
| ExecuteCli privilege | Prefer allowlisted subcommands Zig will proxy; validate paths | `mod.zig` proxy, `daemon.zig` |

**Acceptance:**

- [ ] Size limit + timeout tests
- [ ] Stale socket recovery test
- [ ] Doctor flags untrusted daemon binary path when detectable

---

### 4.3 Policy engine

**Goal:** Non-shell policy cannot be trivially bypassed or misloaded.

| Item | Description | Key paths |
|------|-------------|-----------|
| Validate expansion | Control chars, traversal, huge policies, weird globs | `policy/validate.zig`, `load.zig` |
| Matcher equivalence | bare `.git` vs `./.git`, symlink classes | `policy/matchers.zig` |
| Evaluate completeness | All action kinds; no silent default-allow on unknown | `policy/evaluate.zig` |
| Preset snapshots | Preset → expected policy shape tests | `policy/presets.zig` |
| Immutability | Avoid mutating shared compiled policy | policy modules |

**Acceptance:**

- [ ] New validation rejection tests for hostile patterns
- [ ] Path equivalence table tests
- [ ] Unknown action kind fails closed or errors explicitly

---

### 4.4 Secrets, audit, presentation

**Goal:** No raw secrets on any user-visible or persisted presentation path.

| Item | Description | Key paths |
|------|-------------|-----------|
| Redaction sinks | doctor, report, replay, dashboard feed, deny footers, hooks | `audit/`, `rust_visibility.zig`, dashboard |
| Hash chain / replay | Truncated/reordered/forged events | `audit/hash_chain.zig`, `replay` |
| Silent parse skip | Prefer count/skip with signal; `--verify` fails on corruption | `report.zig`, `dashboard/mod.zig` (`catch continue`) |
| Fixture hygiene | Synthetic secrets only; CI grep for key patterns | `tests/`, fixtures |

**Acceptance:**

- [ ] Synthetic secret appears in event input; never in doctor/report/replay/dashboard output
- [ ] Replay `--verify` fails on broken chain
- [ ] CI secret-pattern grep on fixtures (allowlist synthetic only)

---

### 4.5 Process runtime (intercept, run, sandbox)

**Goal:** Reduce blast radius of supervised agents.

| Item | Description | Key paths |
|------|-------------|-----------|
| Env filtering | Strict allowlists; secret-like names; secretless refs | `intercept/env.zig` |
| Approvals | TTY vs non-TTY; no auto-allow on EOF in strict/ci | `intercept/approvals.zig` |
| Sandbox honesty | doctor truth vs enforcement; no false “active” | `sandbox/*`, `doctor.zig` |
| Network proxy | Destination rules; no credential leak in logs | intercept/network, proxy |
| Staging | `diff`/`apply`/`discard` path containment | apply/diff/discard CLI |

**Acceptance:**

- [ ] Env inheritance tests for secret-like keys
- [ ] Strict/ci EOF on ask → deny/fail (not allow)
- [ ] Staging refuses apply outside workspace root

---

### 4.6 MCP

**Goal:** MCP proxy does not become an exfil channel.

| Item | Description | Key paths |
|------|-------------|-----------|
| Transport | Timeouts; don’t swallow flush without audit | `mcp/transport.zig` |
| Trust/allowlist | Server identity + tool allow/deny | `mcp/`, policy mcp rules |
| Redteam | Fixtures for MCP read of `.env` / secrets | `redteam`, fixtures |

**Acceptance:**

- [ ] Hung MCP server hits timeout
- [ ] Redteam fixture for MCP sensitive read denied

---

### 4.7 Dashboard & local HTTP

**Goal:** Local ops UI cannot escalate or XSS.

| Item | Description | Key paths |
|------|-------------|-----------|
| Action allowlist | Server-side only; reject unknown IDs | `cli/dashboard.zig`, `dashboard/` |
| Workspace trust | Serve only under workspace; no open proxy | dashboard server |
| Bind | Localhost-only by default; document LAN risk | dashboard start |
| XSS | Escape all dynamic fields (`innerHTML`) | `dashboard/assets/app.js` |
| Cleanup | Remove stale `.bak` if present | `dashboard.zig.bak`, `mcp.zig.bak`, etc. |

**Acceptance:**

- [ ] Unknown action ID rejected in tests
- [ ] XSS-oriented fixture escaped in UI path
- [ ] No tracked `.bak` sources in `src/cli/`

---

### 4.8 Plugins & install

**Goal:** Install never lies about protection.

| Item | Description | Key paths |
|------|-------------|-----------|
| Path traversal | Install only under known host config dirs | `plugin_install.zig`, `plugin.zig` |
| Idempotent install | No clobber of unrelated hooks; refuse malformed JSON | plugin modules |
| Smoke deny | Protected only if deny smoke passes (P1) | plugin install, doctor |
| ORCA_BIN trust | Prefer absolute executables; warn on odd paths | hermes plugin / resolve |

**Acceptance:**

- [ ] Malformed host config install fails closed
- [ ] Doctor/plugin doctor never green without smoke when smoke is required

---

### 4.9 Memory, errors, Zig 0.16 hygiene

| Item | Description |
|------|-------------|
| Allocator discipline | Arena per short-lived hook request; errdefer on owned slices; optional OOM fuzz |
| Error sets | Narrow at boundaries; avoid bare `anyerror` where practical |
| Silent catch / unreachable | Audit `catch {}`, `catch continue`, `unreachable` on production paths |
| Buffer safety | Fixed buffers: truncation tests, no overflow |
| Formatting | `zig fmt`, 120 cols, CI enforce |
| Dead code | Delete `.bak` and unused modules |

**Acceptance:**

- [ ] Documented audit of silent catch on hot paths
- [ ] zig fmt clean in CI

---

### 4.10 Testing & automation

| Layer | Action |
|-------|--------|
| Unit | Policy, shell_eval mode matrix, daemon parse tables |
| Integration | Extend `tests/phase2*` host event matrices |
| Fuzz | Hook JSON, policy YAML, daemon NDJSON (`zig build fuzz`) |
| Redteam | Grow fixtures; `orca redteam --ci` in pre-merge where feasible |
| Gates | `test-fast` always; `verify-pre-merge.sh` for releases |
| Secret grep | CI on fixtures and generated reports |

**Acceptance:**

- [ ] Fail-closed matrix in CI
- [ ] Fuzz job non-zero corpus smoke (even short)
- [ ] Redteam CI path documented and green on main

---

### 4.11 Structure & maintainability (after safety)

| Item | Description |
|------|-------------|
| Split mega-files | Extract host mappers from `hook.zig` / `plugin.zig` / `mod.zig` |
| Shared Decision type | allow/warn/ask/deny + rule_id + remediation for run, hook, feed, status |
| Contract tests | Schemas in `integrations/common/schemas` ↔ Zig parse round-trip |
| Feature flags | Experimental hosts opt-in |
| Threat model sync | `docs/threat-model.md` ↔ doctor capabilities |

---

## 5. Explicit non-goals

- Reimplement pack regex/AST/heredoc engine in Zig
- Merge Zig and Cargo build systems
- User-facing “dcg” binary or dual-hook install
- SaaS/telemetry/cloud dashboard (unless product asks)
- Style-only mass refactors unrelated to security boundaries
- Perfect OS sandbox claims on platforms where doctor reports observe-only

---

## 6. Phased execution plan

### Phase ZH-0 — Baseline inventory (0.5–1 day)

- [ ] Inventory shell entrypoints (hook hosts, run, shim)
- [ ] Inventory presentation sinks (doctor, report, replay, dashboard, deny UX)
- [ ] Inventory silent `catch continue` / `catch {}` on hot paths
- [ ] List tracked `.bak` / dead files for deletion
- [ ] Snapshot current `test-fast` / redteam / fuzz commands

**Exit:** Written inventory in this file’s appendix or a short handoff note under `planning/handoffs/`.

### Phase ZH-1 — Control plane + fail-closed (highest ROI)

- [ ] Fail-closed matrix tests for shell paths
- [ ] No Zig shell-eval fallback enforcement + test
- [ ] Host adapter hostile-payload tests for primary hosts
- [ ] Status/doctor honesty fixes if gaps found

**Exit:** CI proves daemon-down ⇒ deny for shell; no false “protected.”

### Phase ZH-2 — Redaction + audit integrity

- [ ] Cross-surface synthetic secret tests
- [ ] Replay verify failure modes
- [ ] Tighten silent event parse skips under verify
- [ ] Fixture secret-pattern CI check

**Exit:** Synthetic secrets never appear on presentation sinks.

### Phase ZH-3 — Daemon IPC hardening

- [ ] Line size limits + timeouts
- [ ] Stale socket / race tests
- [ ] Daemon binary path trust checks in doctor

**Exit:** Client survives hostile/slow daemon without hang or false allow.

### Phase ZH-4 — Policy + runtime + MCP

- [ ] Validation/matcher expansions
- [ ] Env/approvals/staging tests
- [ ] MCP timeout + redteam fixture
- [ ] Sandbox honesty checks where testable

**Exit:** Non-shell bypass and env leak classes covered by tests.

### Phase ZH-5 — Dashboard + plugins cleanup

- [ ] Dashboard action allowlist completeness
- [ ] XSS escape audit
- [ ] Bind defaults documented
- [ ] Delete `.bak` sources
- [ ] Plugin install path safety + smoke honesty

**Exit:** Local UI and install paths meet allowlist + honesty bar.

### Phase ZH-6 — Fuzz, structure, docs

- [ ] Expand fuzz targets
- [ ] Shared Decision type extraction (if still duplicated)
- [ ] Split largest modules if needed for reviewability
- [ ] Align threat-model doc with doctor

**Exit:** Hardening is continuous (fuzz/redteam), not one-off.

---

## 7. Suggested priority sequence (summary)

1. Shell fail-closed matrix + no fallback  
2. Redaction on all presentation sinks  
3. Daemon IPC timeouts / size limits / stale socket  
4. Policy validation + matcher equivalence  
5. Dashboard allowlist + XSS/bind  
6. MCP proxy + redteam  
7. Fuzz hook/policy/daemon inputs  
8. Module splits + delete `.bak`  
9. Sandbox honesty tests per OS  

---

## 8. Verification commands

Narrow → wide (from `AGENTS.md`):

```bash
./scripts/zig build
./scripts/zig build test-fast
./scripts/test-fast.sh
./scripts/zig build test
./scripts/zig build fuzz    # when available
./zig-out/bin/orca redteam --ci
./zig-out/bin/orca doctor
./scripts/verify-pre-merge.sh
```

Do not claim hardening complete without evidence from these gates on the changed areas.

---

## 9. Definition of done (plan-level)

Zig hardening is “good enough for release confidence” when:

1. **Shell:** Daemon failure cannot produce allow on shell control paths (tests).  
2. **Secrets:** Synthetic secrets never leak on presentation sinks (tests + CI grep).  
3. **IPC:** Client timeouts and size limits prevent hang/false allow (tests).  
4. **Policy:** Hostile policy inputs rejected; matchers cover known path forms (tests).  
5. **Dashboard/plugins:** Allowlisted actions; install honesty; no stale attack-surface files.  
6. **Automation:** Fail-closed + redaction + redteam/fuzz wired into regular gates.

Remaining work is continuous pack quality (Rust) and product UX (P2c/P3), not control-plane truth.

---

## 10. Relationship to product roadmap

| Product phase | Zig hardening interaction |
|---------------|---------------------------|
| P0/P1 UX | Already exercise hooks/doctor; hardening adds regression locks |
| P2a packs/status | Status honesty ties to ZH-1 |
| P2b modes | Mode matrix tests live under ZH-1 |
| P2c Pi/dashboard | Dashboard ZH-5; Pi expand is TS + evaluate honesty |
| P3 MCP/custom packs | MCP ZH-4 + policy |

Prefer **small hardening PRs** stacked with product work rather than a single mega-branch.

---

## 11. Appendix A — Known risk markers (snapshot)

Observed during plan drafting (non-exhaustive; re-audit in ZH-0):

- Silent/skip patterns: `catch continue` in `report.zig`, `dashboard/mod.zig`, `ci_check.zig`
- Empty catch: `mcp/transport.zig` flush
- `unreachable` in `policy/presets.zig` (confirm invariant-only)
- Backup noise: `src/cli/*.bak` if still present
- Large control files: `hook.zig`, `plugin.zig`, `mod.zig` — candidates for later split

---

## 12. Appendix B — Document control

| Field | Value |
|-------|--------|
| Location | `docs/dev/zig-hardening-plan.md` (tracked) |
| Audience | Implementers, reviewers, and contributors |
| Related | `docs/threat-model.md`, `docs/dev/security-invariants.md`, `docs/dev/production-readiness-gates.md`, `SECURITY.md` |
| Local drafts | Session notes may live under `planning/`; this file is the published plan |

---

*End of plan.*
