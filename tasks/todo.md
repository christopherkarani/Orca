# Phase 21 Documentation and Demo Plan

## Assumptions

- Phase 21 is documentation, examples, and deterministic demo work only.
- Existing CLI/runtime behavior is the source of truth; docs must not claim stronger transparent filesystem or network enforcement than `aegis doctor` reports.
- The leaky-agent demo must use synthetic data only, require no LLM, require no external network, and leave no raw fake secret in audit, replay, summary, README, or docs.
- Example policies should use existing policy schema and must pass `aegis policy check`.
- Install documentation must match the Phase 19 scripts and packaging templates already present in the repo.

## Research Check

- [x] Read required Phase 21 context files and project lessons.
- [x] Start read-only subagent checks for CLI behavior and documentation gaps.
- [x] Inventory current CLI help, release scripts, packaging templates, policies, and red-team fixture behavior.
- [x] Re-check assumptions after writing docs to identify false positives, gaps, and overclaims.

## TDD/Validation Checklist

- [x] Create or update launch README with honest positioning, examples, platform matrix, docs links, contribution and disclosure paths.
- [x] Create deterministic `examples/leaky-agent-demo/` with fake agent, local policy, scripts, expected-output notes, and no raw fake secret persistence.
- [x] Create or update all requested documentation pages under `docs/`.
- [x] Create documented examples under `examples/policies`, `examples/mcp`, `examples/ci`, `examples/staged-writes`, `examples/network`, and `examples/commands`.
- [x] Create or update compatibility matrix using actual `aegis doctor` capability vocabulary.
- [x] Add practical documentation validation checks for README/doc links, example policy validation, demo execution, and fake-secret scans.
- [x] Validate all example and preset policies with `aegis policy check`.
- [x] Manually verify quickstart/demo/replay flows from a clean temporary checkout.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis version --json`
- [x] `./zig-out/bin/aegis policy check` for every example and preset policy.
- [x] README links and docs links point to existing files.
- [x] Leaky-agent demo runs without real LLMs, real secrets, or external network.
- [x] `aegis replay --session last --verify` works after the demo.
- [x] Fake secret values do not appear in persistent demo logs, replay output, README, or docs.

## Review

- Launch README now documents positioning, install, quickstart, demo, run/replay/staging/MCP/red-team examples, platform matrix, protections, non-promises, Why Zig, contribution, security disclosure, and docs links.
- Added requested launch docs under `docs/` plus a consolidated compatibility matrix using `aegis doctor` capability vocabulary.
- Added `examples/leaky-agent-demo/` with a temporary-workspace fake-agent demo, policy, POSIX and PowerShell scripts, expected-output notes, and runtime fake-secret scanning.
- Added documented examples for policies, MCP, CI, staged writes, network, and command guard.
- Added `scripts/validate-docs.sh` for markdown link checks, example policy checks, MCP manifest check, demo execution, fake-secret scan, and limitation wording checks.
- Clean-copy quickstart smoke passed from `/tmp/aegis-clean.WZDxKg/aegis`: build, init, policy check, doctor, `aegis run -- echo hello`, replay verify, and red-team CI.
- Verification passed: `zig build`, `zig build test`, `./zig-out/bin/aegis redteam --ci` with 10/10 fixtures, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis version --json`, all example/preset policy checks, `scripts/validate-docs.sh`, MCP manifest check, fake-secret grep, overclaim grep, and `git diff --check`.

Known limitations:

- Demo demonstrates Aegis-mediated command denial, network policy decisions, audit, redaction, and replay; it intentionally does not claim transparent arbitrary file-read interception.
- macOS docs reflect current local `doctor` output: transparent network and filesystem enforcement are limited, proxy-mediated network enforcement and strong sandbox are unavailable.
- The PowerShell demo script is provided, but this run verified the POSIX script on macOS.
