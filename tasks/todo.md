# Phase 18 Agent Presets and Integrations Plan

## Assumptions

- Phase 18 is limited to practical local/CI adoption: editable policy presets, init preset selection, completions, GitHub Actions examples, doctor checks, and docs.
- Presets must validate with the existing policy schema; comments are allowed because the YAML parser strips comments before parsing.
- Agent-specific presets are conservative generic starting points unless Aegis has verifiable public behavior for that agent; docs and init warnings must say so.
- CI integration is local/repo-only and must not assume hosted Aegis, external services, real tokens, or model-provider-specific secrets.
- Doctor may report binaries/manifests/environment when detected, but binary presence is not a security proof.

## Research Check

- [x] Read Phase 18 and required canonical, architecture, security, and production gate docs.
- [x] Review project lessons for phase-driven Aegis pitfalls: no untracked command modules, honest capability labels, CI non-interactive behavior, deny priority, redaction.
- [x] Inspect current init, policy presets/load/validate, completions stub, help routing, doctor/platform capability reporting, and docs state.
- [x] Capture baseline verification before implementation.
- [x] Validate false-positive risks before broad edits: preset comments must parse, generated policies must not contain fake secrets, doctor must not print raw env values, and docs must avoid sandbox overclaims.

## Checklist

- [x] Add failing/focused tests for Phase 18 presets, init preset behavior, completions output, CI example presence, and doctor policy/secret reporting.
- [x] Add `policies/presets/*.yaml` for all requested presets with safe comments and no secrets.
- [x] Wire preset metadata/content into `aegis init --preset ...`, preserving no-overwrite unless `--force` and warning for generic/experimental presets.
- [x] Implement shell completions for bash, zsh, fish, and PowerShell with top-level commands and common flags.
- [x] Improve doctor integration checks for Git, workspace root, policy presence/validity, known agent binaries, MCP manifests, CI environment, shell type, platform backend status, audit/replay, red-team fixtures, and next-step recommendations.
- [x] Add GitHub Actions reusable action/example workflow docs with audit artifact upload and `aegis redteam --ci`, with no real tokens.
- [x] Add/update docs for presets, agent recipes, CI, quickstart/README as needed with honest limitations.
- [x] Run required verification: `zig build`, `zig build test`, `./zig-out/bin/aegis redteam --ci`, and `aegis policy check` for every preset.
- [x] Run manual smokes requested by the user and inspect generated/audit/replay outputs for synthetic secrets.
- [x] Document review results, preset validation, integration support status, security notes, known limitations, and acceptance criteria status.

## Review

- Baseline verification before Phase 18 changes: `zig build` passed.
- Baseline verification before Phase 18 changes: `zig build test` passed.
- Implemented ten editable YAML presets under `policies/presets/`; all validate with `aegis policy check`.
- Implemented `aegis init --preset` for all requested preset names, preserved no-overwrite behavior, added `--force`, and prints next steps plus generic/experimental warnings for agent-specific presets.
- Implemented shell completion generation for bash, zsh, fish, and PowerShell and added CLI dispatch/help.
- Improved `aegis doctor` with integration checks for workspace, Git, policy presence/validity, PATH agent binaries, MCP manifests, CI detection, shell type, audit/replay, red-team fixtures, platform backend status, and next-step recommendation.
- Added GitHub Actions composite action metadata and CI docs with audit artifact upload and `aegis redteam --ci`.
- Added docs for presets, agent recipes, CI, quickstart, and updated stale README/docs/policies wording to avoid unsupported sandbox claims.
- Final verification: `zig build` passed.
- Final verification: `zig build test` passed.
- Final verification: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- Final verification: every file under `policies/presets/*.yaml` passed `./zig-out/bin/aegis policy check`.
- Manual smoke in a temp workspace: `aegis init --preset generic-agent --force` created a valid ask-mode policy; `aegis policy check .aegis/policy.yaml` passed.
- Manual smoke in a temp workspace: `aegis init --preset github-actions --force` created a valid ci-mode policy; `aegis doctor` reported `.aegis/policy.yaml: present and valid`.
- Manual smoke: completions for bash, zsh, fish, and powershell were non-empty.
- Manual smoke: invalid preset name failed clearly with an unsupported preset error.
- Manual smoke: generated policies, doctor output, `events.jsonl`, and replay output did not contain the synthetic secret `ghp_fakeSecretShouldNotPrint`.
- Known limitation: installed binaries do not yet package external `policies/presets/` files; `aegis init` uses embedded preset text and Phase 19 should align release packaging.
- Known limitation: doctor binary detection reports PATH presence only and does not prove an agent is configured or secure.
- Known limitation: shell completions are static top-level/common-flag completions, not full context-aware subcommand completion.
