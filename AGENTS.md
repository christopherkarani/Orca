# Orca Agent Instructions

## Public Repository Hygiene

- Treat this repository as a public-facing GitHub repo by default.
- Do not track private planning, marketing, GTM, customer-pilot, founder-led sales, launch-ops, release-draft, generated evidence, or local agent task files.
- Keep these surfaces local-only unless the user explicitly asks to publish a specific artifact:
  - `go_to_market/`
  - `customer_pilot/`
  - `tasks/`
  - `reports/`
  - `.orca-edge/`
  - `.edge/`
  - `dist/`
  - `dist-dry-run/`
  - `docs/release/`
  - `docs/orca_opencode_openclaw_plan/`
  - `integrations/**/node_modules/`
- Before staging or committing, run a tracked-file hygiene check for private/public-boundary leaks:
  - `git ls-files | rg '(^go_to_market/|^customer_pilot/|^tasks/|^reports/|^\\.orca-edge/|^\\.edge/|^dist/|^dist-dry-run/|^docs/release/|^docs/orca_opencode_openclaw_plan/|node_modules/)'
- If that command returns any files, stop and untrack them before proceeding.
- Never commit generated release archives, SBOMs, checksums, dry-run package output, red-team replay output, customer-pilot templates, SOW/NDA notes, target-account templates, outreach copy, pricing guidance, or task-memory logs.

## Zig toolchain (mandatory)

- **Pinned version:** Zig **0.16.0** (see `.zigversion`, `build.zig.zon`, and CI).
- **Never run bare `zig build` / `zig build test` in this repo** unless `zig version` is already `0.16.0`. Prefer **`./scripts/zig`** (always uses the pinned toolchain). Optional: `direnv allow` (`.envrc`) or `eval "$(./scripts/ensure-zig-toolchain.sh --export)"` in your shell.
- If `zig build` fails and `zig version` is not `0.16.0`, **stop and fix the toolchain** (`./scripts/ensure-zig-toolchain.sh --install`) before treating failures as source bugs.
- **Ignore stale local scratch:** `.orchestrator/` is gitignored; do not commit migration plans or agent session artifacts from there.

## Fast iteration (local verify)

Use the narrowest gate that matches the change; reserve the full suite for pre-merge/CI.

| Tier | Command | When |
|------|---------|------|
| 1 | `./scripts/zig build` | After compile-touching edits |
| 2 | `./scripts/zig build test-fast` | Default unit gate (orca lib + `orca_core`; ~minutes → often ~10s warm) |
| 3 | `./scripts/quick-install-dx-verify.sh` | Preset / quick-install / `generic-agent` policy |
| 4 | `./scripts/test-fast.sh` | Tiers 1–3 in one script |
| 5 | `./scripts/zig build test` | Pre-merge / CI (all plugin/phase/setup/fuzz suites) |
| 6 | `./scripts/verify-pre-merge.sh` | Tiers 1–4 + full `build test` in one script |

**Agents and automation:** Do not pipe long builds to `tail` (output buffers until completion). Do not background full `zig build test` unless you will poll to completion. Do not prefix commands with system `zig version`—use `./scripts/zig version` only.

## Workflow

- Preserve user-owned dirty changes. Do not revert unrelated edits.
- Use TDD for non-trivial code changes: write or update focused tests before implementation when practical.
- Keep changes surgical and tied to the user request.
- Verify before calling work complete. For code changes, run the narrowest meaningful test first, then broader checks when the blast radius justifies it.
- For audits, lead with concrete file-backed findings and avoid speculative cleanup.

## Product Boundary

- Keep public Core/Orca surfaces separate from internal Orca Edge, customer acquisition, and pilot-planning collateral.
- Public docs may explain supported behavior, installation, security model, and verified limitations.
- Internal docs may plan launches, pilots, pricing, outreach, target accounts, release operations, or founder/customer strategy, but those stay untracked unless explicitly approved for publication.
