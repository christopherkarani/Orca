# Orca Agent Instructions

## Working Style

- Verify the real checkout and files before changing anything.
- Use TDD for non-trivial changes.
- Keep edits surgical and tied to the request.
- Default to direct work for small or mechanical tasks.
- Use subagents only when the task spans multiple files/modules, needs isolated review, or has meaningful architectural risk.
- If you use subagents, write a short plan first and treat their output as advisory until verified.

## Repo Boundaries

- Treat this repository as public-facing by default.
- Keep local planning, handoffs, reviews, and task notes out of tracked docs unless the user explicitly asks to publish them.
- Keep session-local artifacts in `planning/`; only `planning/README.md` is tracked.
- Before staging or committing, run:

```bash
git ls-files | rg '(^planning/|^go_to_market/|^customer_pilot/|^tasks/|^reports/|^\\.orca-edge/|^\\.edge/|^dist/|^dist-dry-run/|^docs/release/|^docs/orca_opencode_openclaw_plan/|node_modules/)'
```

- Never commit generated release archives, SBOMs, checksums, dry-run package output, red-team replay output, customer-pilot templates, SOW/NDA notes, target-account templates, outreach copy, pricing guidance, or task-memory logs.

## Orca Context

- Zig is the primary user-facing CLI.
- Rust runs the background daemon and evaluator service.
- Shell commands route through the Rust evaluator; non-shell events stay in Zig.
- Do not invoke `cargo` from `zig build`.
- If the daemon is unavailable, `orca hook` must fail closed with `deny`.
- Read `planning/migration/MERGE_ORCA_RS_INTO_ORCA_CLI_v2.md` for migration work only.

## Toolchain

- Use Zig **0.16.0** (`.zigversion`).
- Prefer `./scripts/zig` over bare `zig` / `zig build` / `zig build test`.
- If a Zig command fails and the version is wrong, fix the toolchain first:

```bash
./scripts/ensure-zig-toolchain.sh --install
eval "$(./scripts/ensure-zig-toolchain.sh --export)"   # or: direnv allow
./scripts/zig version   # must print 0.16.0
```

- Rust lives in `orca-rs/` with its own `Cargo.toml` and toolchain file. Keep the Zig and Cargo graphs separate.

## Verification gates (read this before every verify loop)

**Default: use the narrowest gate that can catch your change.**
“test-fast” means *fast relative to the full suite*, not “seconds.” The Zig lib unit binary alone is often **several minutes** (~1.1k tests via the monopath `src/root.zig` graph).

**One-shot path picker for agents:**

```bash
./scripts/agent-gate.sh              # auto from git dirty paths
./scripts/agent-gate.sh --dry-run    # print selection only
./scripts/agent-gate.sh units        # force L1
./scripts/agent-gate.sh --paths src/cli/plugin.zig
```

### Tier ladder

| Tier | When | Command | Typical cost |
|------|------|---------|--------------|
| **L0 compile** | After every Zig edit; “does it compile?” | `./scripts/compile-fast.sh check` | ~seconds–tens of seconds |
| **L0 compile tests** | After test-graph / lib-heavy edits | `./scripts/compile-fast.sh test-lib` or `test-fast` | compile only, no run |
| **L0.5 domain** | Edits confined to one domain | `./scripts/test-slice.sh sandbox\|policy\|intercept` | often **seconds–tens of seconds** |
| **L1 units** | Broad Zig logic needs unit confidence | `./scripts/test-fast.sh units` **or** monopath `test-lib` | **multi-minute** monopath |
| **L2 product** | Policy/CLI handoff, pre-PR light gate | `./scripts/test-fast.sh` (or `full`) | L1 + ~1s quick-install matrix |
| **L3 full Zig** | Pre-merge / full suite (single CI job) | `./scripts/zig build test` | full phase/plugin/fuzz suites |
| **L4 pre-merge** | Explicit pre-merge only | `./scripts/verify-pre-merge.sh` | L2 + L3 + install/uninstall regressions |

```bash
# L0 — preferred agent iteration for Zig
./scripts/compile-fast.sh              # = check (CLI only)
./scripts/compile-fast.sh check
./scripts/compile-fast.sh test-lib     # compile lib tests, no run
./scripts/compile-fast.sh test-fast    # compile test-fast set, no run
./scripts/compile-fast.sh test-lib-run # compile + run lib tests (serial)
./scripts/compile-fast.sh test-fast-run

# Path-aware shortcut
./scripts/agent-gate.sh

# L1 / L2 — test-fast.sh modes (incremental + -j1)
./scripts/test-fast.sh compile         # build CLI + compile test-fast artifacts
./scripts/test-fast.sh units           # + run unit binaries (no quick-install)
./scripts/test-fast.sh full            # + quick-install matrix (default)
./scripts/test-fast.sh                 # same as full
ORCA_TEST_FAST=units ./scripts/test-fast.sh

# L0.5 domain slices (prefer over monopath when paths stay in-domain)
./scripts/test-slice.sh sandbox
./scripts/test-slice.sh policy
./scripts/test-slice.sh intercept
./scripts/test-slice.sh sandbox --filter Seatbelt
./scripts/agent-gate.sh sandbox   # or auto when only src/sandbox/* is dirty

# Name filter (Zig 0.16: compile-time -Dtest-filter, NOT runtime -- --test-filter)
./scripts/zig build test-lib -Dtest-filter=Spinner
./scripts/test-slice.sh lib --filter Spinner

# Focused Zig steps (when you know the surface)
./scripts/zig build check
./scripts/zig build test-lib
./scripts/zig build test-core
./scripts/zig build test-core-contract
./scripts/zig build test-sandbox
./scripts/zig build test-policy
./scripts/zig build test-intercept
./scripts/zig build test-fast
./scripts/zig build compile-test-lib
./scripts/zig build compile-test-fast   # same membership as test-fast (no run)

# Local mirror of fast PR signal
./scripts/ci-local-fast.sh              # zig units; + rust --lib if orca-rs dirty
./scripts/ci-local-fast.sh --with-rust

# L3 / L4 — do not use mid-slice
./scripts/zig build test
./scripts/verify-pre-merge.sh
```

### Path → gate matrix

| Touched paths | Prefer |
|---------------|--------|
| Single Zig file, compile check only | **L0** `./scripts/compile-fast.sh check` |
| `src/sandbox/**` only | **L0.5** `./scripts/test-slice.sh sandbox` / `agent-gate.sh` |
| `src/policy/**` only | **L0.5** `./scripts/test-slice.sh policy` (core package gates; monopath L1 if needed) |
| `src/intercept/**` only | **L0.5** `./scripts/test-slice.sh intercept` |
| `src/**`, `packages/**`, `build.zig` (broad logic) | L0 → **L1** `test-fast.sh units` or `agent-gate.sh` |
| `packages/core/**` only | `./scripts/agent-gate.sh core` or `zig build test-core` + `test-core-contract` |
| `policies/**`, init/preset DX | L0 + `./scripts/quick-install-dx-verify.sh` (or L2 full) |
| `orca-rs/**` only | `./scripts/agent-gate.sh rust` or `(cd orca-rs && cargo test --lib)` |
| `integrations/*-plugin/**` | `./scripts/agent-gate.sh plugin` (package-local `npm test` / python unittest) — **not** full Zig suite |
| `orca-dashboard-ui/**` or `src/dashboard/**` | `./scripts/agent-gate.sh dashboard` (`npm test` in `orca-dashboard-ui/`; CI path-filtered) |
| `scripts/**` only | `bash -n` + the script’s own smoke; avoid L3 unless the script is a gate itself |
| Mixed Zig + Rust | Run **each stack’s** narrow gate; never assume one covers the other |

### Rust gates

```bash
cd orca-rs
cargo test --lib          # default agent gate (fast, large suite)
cargo test                # broader (integration bins); use when needed
cargo clippy --all-targets
cargo build               # debug daemon; prefer over release for iteration
```

### Script catalog (agent-relevant)

| Script | Role |
|--------|------|
| `./scripts/zig` | Pinned Zig 0.16.0 wrapper — **always** use this |
| `./scripts/ensure-zig-toolchain.sh` | Install/check/export toolchain |
| `./scripts/compile-fast.sh` | **Fastest** Zig compile iteration (incremental; parallel for compile-only) |
| `./scripts/test-fast.sh` | L1/L2 gate with `compile` / `units` / `full` modes + step timings + incremental |
| `./scripts/agent-gate.sh` | Path-aware narrowest gate (auto / dry-run / forced mode; domain slices) |
| `./scripts/test-slice.sh` | Domain units + `-Dtest-filter` (`sandbox` / `policy` / `intercept` / `lib` / …) |
| `./scripts/ci-local-fast.sh` | Local mirror of fast PR signal (Zig units ± `cargo test --lib`) |
| `./scripts/quick-install-dx-verify.sh` | Cheap policy matrix (~1s once CLI is built) |
| `./scripts/verify-pre-merge.sh` | L4 kitchen sink — **pre-merge only** |
| `./scripts/assert-zig-build-no-cargo.sh` | Guards dual-stack rule |
| `./scripts/build-all.sh` | Builds Zig CLI **and** **release** daemon — **not** for everyday iteration |
| `scripts/README.md` | Iteration gates + release helpers |
| `tests/slices/README.md` | Domain slice map |

### Optimizations already in place

- `compile-fast.sh` uses `-fincremental -Dincremental=true`. **Compile-only** modes use the default job count; **run** modes use `-j1` so test binaries stay serial (parallel test runs have hung with no output on some hosts).
- `test-fast.sh` uses the same incremental + `-j1` flags and prints per-step wall times (`[test-fast] … done in Ns`).
- `build.zig` step `test-fast` serializes lib → core package → core contract for hang avoidance.
- `compile-test-fast` membership **matches** `test-fast` (lib + orca_core package + core contract). Daemon IPC hardening is full-suite only.
- Domain steps `test-sandbox` / `test-policy` / `test-intercept` avoid the full CLI/TUI monopath when work stays in-domain.
- Unit name filters use **`-Dtest-filter=…`** at build time (Zig 0.16 compile filters). Runtime `-- --test-filter` on the terminal runner is invalid.
- CI: `ci.yml` runs **fast** Zig (`test-fast`) + Rust `--lib` then full; `test.yml` is the **only** full `zig build test` job; dashboard is path-filtered.
- Tests use `addRunTestTerminal` (`stdio = .inherit`) so Zig 0.16 **server-mode** (`--listen=-`) is avoided — server mode deadlocks if the protocol peer never speaks.
- Plugin doctor PATH lookups share one env snapshot; OOM-fail tests on doctor use a **tiny owned-field harness**, not full doctor collect (see pitfalls).

### Pitfalls (do not)

1. **Do not** default every edit to `verify-pre-merge.sh` or `./scripts/zig build test`. Those are L3/L4.
2. **Do not** treat “test-fast” as a 10-second gate. Budget **minutes** for L1 monopath; prefer domain slices / filters when possible.
3. **Do not** use `./scripts/build-all.sh` for iteration — it `cargo build --release` the daemon.
4. **Do not** invoke `cargo` from `zig build` or reverse (dual-stack rule).
5. **Do not** pipe long builds to `tail`, and do not background `./scripts/zig build test` unless you poll to completion.
6. **Do not** use `zig build test-lib -- --test-filter …` — that ABRTs under the terminal runner. Use **`-Dtest-filter=…`** or `./scripts/test-slice.sh … --filter …`.
7. **Do not** run dashboard/plugin npm suites because a Zig/Rust file changed (or vice versa).
8. **Do not** clear `.zig-cache` / `orca-rs/target` as a first response to a failure — fix the error; caches are large and cold rebuilds hurt.
9. **Do not** assume Zig and Rust evaluators are interchangeable. Fail closed on daemon unavailability for shell hooks.
10. **Do not** commit `planning/` task notes, `dist/`, SBOMs, or secret-bearing fixtures (see Repo Boundaries).
11. **Do not** wrap heavy FS/PATH/env collectors in `std.testing.checkAllAllocationFailures` (e.g. full `collectPluginDoctorReport*`). That re-runs the whole function per alloc index and **looks hung for minutes** with high CPU / growing RSS. Use a small owned-field harness instead.
12. **Do not** reintroduce default `b.addRunArtifact(test)` for the monopath suite without terminal-mode stdio — server-mode IPC hangs on stdin.
13. **Do not** assume silence = hang under a TTY: the terminal runner uses Progress and may print little until a long test finishes. Force line mode with `… 2>&1 | cat` if you need per-test lines; if CPU is pegged, `sample <pid>` the test process.

### If test-fast “hangs”

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| High CPU, RSS climbing, no new lines for 1–3+ min | Pathological unit test (historically OOM-fail on full doctor collect) | `sample <pid>`; fix the test, don’t kill the toolchain |
| Zero CPU, stuck, process args include `--listen=-` | Zig 0.16 server-mode test IPC | Ensure tests use `addRunTestTerminal` / `stdio = .inherit` |
| Completes in ~few minutes total | Normal L1 monopath cost | Prefer L0 / `agent-gate.sh`; don’t “fix” by skipping verify |
| Parallel multi-binary run silent | Known host hang | Keep `-j1` and serialized `test-fast` deps |

### Long build hygiene

- Prefer `./scripts/agent-gate.sh` → `./scripts/compile-fast.sh` / `./scripts/test-fast.sh` over ad-hoc `zig build` flag soup.
- After multi-agent fix waves that touch many modules, re-run **L2 once** before claiming done.
- Warm caches: second run of L0 should be much cheaper than a cold machine; if every L0 costs multi-minute compile, check toolchain version and whether you are accidentally cleaning caches.

## Development Rules

- Preserve user-owned dirty changes.
- Verify before calling work complete (with the **narrowest** gate above).
- Use conventional commits.
- Do not add dependencies without documenting them in `docs/dev/dependencies.md`.
- Do not introduce SaaS, telemetry, monetization, or cloud dashboards unless the user asks for them.
- Do not persist raw secrets in logs, fixtures, reports, docs, tests, or snapshots.

## Long-Running Tasks

- Keep a concise todo list for multi-turn work.
- Record important decisions and blockers in memory when the task spans turns.
- After each implemented slice, note what changed and what remains.

## Code Style

- Zig: `zig fmt`, 4-space indent, 120 column limit.
- Rust: `cargo fmt` and `cargo clippy`.
- Follow `.editorconfig` for file-specific spacing.

## Risk Areas

- Zig and Rust hook evaluators are not interchangeable.
- Keep Zig and Rust build systems separate.
- Do not fall back to Zig native evaluation if the daemon is unavailable.
- Migration phases are ordered; do not skip ahead.
- The Zig **lib test monopath** (`src/root.zig` + `cli/mod.zig` test pulls) is the main local iteration bottleneck — compensate with L0-first discipline, not by skipping verification entirely.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for `christopherkarani/Orca` (via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`CONTEXT.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.
