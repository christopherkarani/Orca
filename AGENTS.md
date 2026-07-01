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

## Toolchain and Verification

- Use Zig 0.16.0.
- Prefer `./scripts/zig` over bare `zig build` or `zig build test`.
- If a Zig command fails and the toolchain version is wrong, fix the toolchain first with `./scripts/ensure-zig-toolchain.sh --install`.
- Use the narrowest useful gate:

```bash
./scripts/zig build
./scripts/zig build test-fast
./scripts/quick-install-dx-verify.sh
./scripts/test-fast.sh
./scripts/zig build test
./scripts/verify-pre-merge.sh
```

- Rust verification lives in `orca-rs/`:

```bash
cargo test
cargo test --lib
```

- For long builds, do not pipe to `tail` and do not background `./scripts/zig build test` unless you will poll it to completion.

## Development Rules

- Preserve user-owned dirty changes.
- Verify before calling work complete.
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
