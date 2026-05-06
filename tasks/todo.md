# Phase 04 CLI Skeleton Plan

## Assumptions

- Phase 04 is CLI-only: no real process supervision, policy matching, MCP proxying, staging engine, or red-team execution.
- Existing Phase 03 core capability model is the source for `doctor`; CLI output must report planned/stub capability status honestly.
- `init` may write a minimal valid-looking YAML policy template directly because full policy parsing belongs to Phase 07.
- Tests should exercise command routing through pure functions and use a temporary directory for `init`.

## Checklist

- [x] Add Phase 04 tests first for top-level help, command help, version aliases, unknown commands, `init`, overwrite refusal, and `doctor`.
- [x] Implement conventional Phase 04 exit code constants.
- [x] Implement command dispatch and command-specific help for all planned commands.
- [x] Implement honest placeholder command handlers for future phases.
- [x] Implement `init` policy creation with `--mode`, `--ci`, `--force`, and overwrite protection.
- [x] Implement `doctor` capability output from `core/platform.zig`.
- [x] Run `zig build`, `zig build test`, and required manual CLI smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Review fix: placeholder commands now return unsupported exit code `4` instead of success when invoked before implementation.
- Review fix: `aegis version --help` now shows command help and `aegis version <extra>` returns usage exit code `2`.
- Manual smoke tests passed:
  - `aegis --help`
  - `aegis help run`
  - `aegis version`
  - `aegis init --mode strict`
  - `aegis doctor`
  - unknown command returned exit code `2`
  - `aegis run -- true` returned unsupported exit code `4`
  - `aegis version --help` returned exit code `0`
  - `aegis version typo` returned usage exit code `2`
- Phase 04 remains CLI-only; no process supervision, policy matching, MCP proxying, staging engine, or red-team execution was implemented.
- `doctor` reports planned capability rows with the existing Phase 03 capability states and does not claim active enforcement.
- `init` writes a minimal `.aegis/policy.yaml`, refuses overwrite without `--force`, and does not persist secrets.

# Phase 05 Session Supervisor Plan

## Assumptions

- Phase 05 owns only direct-child process supervision behind `aegis run`; policy enforcement, audit persistence, env filtering, filesystem staging, command guard, MCP proxying, and sandboxing remain out of scope.
- The CLI should parse `--workspace`, `--mode`, `--session-name`, and `--` while the core supervisor resolves workspace, creates session metadata, launches the child, waits, and reports the result.
- Child stdout/stderr should inherit the terminal for real CLI runs; unit tests should use platform-portable Zig helper invocations or intentionally missing commands.
- Workspace detection should prefer explicit workspace, then nearest parent `.git`, then current working directory, and should not fail outside a Git repository.

## Checklist

- [x] Add Phase 05 tests first for run config parsing, workspace detection, successful child execution, non-zero child exit propagation, missing command errors, and session metadata.
- [x] Implement `src/core/supervisor.zig` with `RunConfig`, `SessionResult`, workspace resolution, session creation, child launch/wait, and exit status mapping.
- [x] Replace `src/cli/run.zig` placeholder with real argument parsing, summary output, useful missing-command errors, and child exit propagation.
- [x] Update run help text to describe Phase 05 options without claiming future enforcement.
- [x] Run `zig build`, `zig build test`, and requested manual smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual smoke tests passed:
  - `zig-out/bin/aegis run -- echo hello` returned exit code `0` and streamed `hello`.
  - `zig-out/bin/aegis run --workspace . -- echo hello` returned exit code `0` and resolved the workspace to this checkout.
  - `zig-out/bin/aegis run --mode observe -- echo hello` returned exit code `0` and printed `Mode: observe`.
  - `zig-out/bin/aegis run -- /bin/sh -c 'exit 7'` returned exit code `7`.
  - `zig-out/bin/aegis run -- aegis-definitely-missing-command` returned exit code `1` with `command not found`.
- Phase 05 is direct-child supervision only. It does not implement policy enforcement, environment filtering, audit persistence, filesystem staging, command guard, MCP proxying, sandboxing, network guard, approvals, or process-tree containment.
- Session lifecycle events are created in memory only for Phase 06 audit integration points; no persistent event log is written.
- Unit tests suppress child stdout/stderr to avoid corrupting Zig's `--listen` build-test protocol; the real CLI inherits child stdio.
- Windows manual smoke was not run from this macOS checkout; the supervisor tests use Zig child commands for portable coverage, and the Unix-specific `/bin/sh -c 'exit 7'` smoke documents the local exit-code propagation check.

## Review Fixes

- [x] Fixed post-spawn start-hook failures so the supervisor kills/reaps the child before returning the hook error.
- [x] Fixed lifecycle event target ownership so returned events do not point at stack-backed `session.id.slice()` storage.
- [x] Added regression tests for hook-failure cleanup and owned session event target values.

# Phase 06 Audit Log and Replay Plan

## Assumptions

- Phase 06 owns persistent audit artifacts for `aegis run` only: no policy enforcement, approvals, command guards, MCP mediation, filesystem staging, network enforcement, or raw child output capture.
- The audit module is the only persistent event writer; CLI and supervisor may create event models but persistence goes through `src/audit`.
- Deterministic event serialization will use explicit stable field ordering for Aegis event fields rather than a general-purpose canonical JSON implementation.
- The hash chain will hash `previous_hash || canonical_event_without_event_hash`, with `previous_hash` represented as the previous event's hex hash or empty bytes for the first event.
- `summary.json` will record bounded session metadata plus the final event hash so `replay --verify` can detect summary tampering as well as event tampering.

## Checklist

- [x] Add Phase 06 tests first for audit directory creation, JSONL writing, stable serialization/hash verification, summary artifacts, last session resolution, replay human output, replay JSON output, denied filtering, and tamper detection.
- [x] Implement audit redaction hook, deterministic event serializer, hash-chain writer, summary writer, and replay verifier.
- [x] Wire `aegis run` to create `.aegis/sessions/<session-id>/`, write events and summaries, and update `.aegis/last` after a completed session.
- [x] Implement `aegis replay` options: `--session last`, `--json`, `--only denied`, and `--verify`.
- [x] Update command help without claiming future-phase enforcement.
- [x] Run `zig build`, `zig build test`, and required manual smoke/tamper checks.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual smoke tests passed:
  - `zig-out/bin/aegis run -- echo hello` returned exit code `0`, streamed `hello`, and created `.aegis/sessions/2026-05-06T17-58-43Z_3cb3/`.
  - `.aegis/sessions/2026-05-06T17-58-43Z_3cb3/events.jsonl` exists and contains `session_start`, `process_launch`, and `session_exit`.
  - `.aegis/last` points to `2026-05-06T17-58-43Z_3cb3`.
  - `zig-out/bin/aegis replay --session last` prints the session timeline.
  - `zig-out/bin/aegis replay --session last --verify` prints `Hash chain: verified`.
  - `zig-out/bin/aegis replay --session last --json` emits a JSON array of events.
  - `zig-out/bin/aegis replay --session last --only denied` succeeds and prints no event rows for this allowed Phase 06 run.
  - Tampering `events.jsonl` by changing `echo hello` to `echo tampered` made `aegis replay --session last --verify` fail with `invalid event_hash`; the file was restored and verification passed again.
- Phase 06 remains audit/replay only. It does not implement policy enforcement, approvals, command guards, MCP mediation, filesystem staging, network enforcement, sandboxing, or raw child output capture.
- The deterministic event format uses explicit stable field ordering for Aegis event fields rather than full generic canonical JSON.
- The redaction hook is intentionally basic in Phase 06; it redacts common secret-shaped strings before event/summary persistence but is not a full redaction engine.

## Review Fixes

- [x] Fixed workspace fallback so a non-Git start directory is preserved instead of resolving to `/` or a parent Git checkout.
- [x] Added a regression test using a temp directory outside the repository for non-Git workspace fallback.
- [x] Hardened audit verification so malformed/missing event fields return verification failure reasons instead of panicking.
- [x] Added malformed-event verification regression coverage.
- [x] Re-ran `zig build`, `zig build test`, a non-Git `aegis run`/`replay --verify` smoke test, and a malformed-event replay failure smoke test.

# Phase 07 Policy Engine Plan

## Assumptions

- Phase 07 is policy evaluation only: no filesystem, command, network, MCP, or sandbox enforcement should be claimed or added yet.
- YAML support can be implemented for the minimum v1 schema without adding a dependency; JSON policies should also parse through Zig's standard JSON parser.
- Policy discovery order is CLI path, workspace `.aegis/policy.yaml`, user config `~/.config/aegis/policy.yaml`, then built-in preset.
- `aegis policy explain` can use the discovered/default policy because the requested command shape has no explicit policy path option.
- `aegis run --policy <path>` should validate/load the policy and audit a `policy_loaded` event, but should still run the child without enforcing policy decisions.

## Research Check

- [x] Read Phase 07, canonical implementation decisions, architecture contracts, security invariants, and production readiness gates.
- [x] Verified existing `src/policy` files are stubs and Phase 06 audit/run wiring is the integration point.
- [x] Verified event type `policy_loaded` already exists and replay can display arbitrary event types from JSONL.

## Checklist

- [x] Add policy tests first for parsing, invalid failures, discovery, modes, matching, explanations, deny priority, and built-in presets.
- [x] Implement versioned policy schema, built-in presets, bounded loading, minimal YAML/JSON parsing, validation, and discovery.
- [x] Implement rule matchers for files, env vars, commands, network domains, and MCP `server.tool` selectors.
- [x] Implement decision priority and explanations with matched rule IDs where possible.
- [x] Implement `aegis policy check` and `aegis policy explain`.
- [x] Wire `aegis run --policy` to load policy and emit a `policy_loaded` audit event without claiming enforcement.
- [x] Add built-in policy files/templates for observe, ask, strict, and ci.
- [x] Run `zig build`, `zig build test`, and required manual smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual policy checks passed:
  - `aegis policy check policies/strict.yaml`
  - `aegis policy check policies/ask.yaml`
  - `aegis policy check policies/observe.yaml`
  - `aegis policy check policies/ci.yaml`
- Manual explanations passed:
  - `aegis policy explain file.read ~/.ssh/id_ed25519` returned `deny` with `files.read.deny[2]`.
  - `aegis policy explain file.read ./.env` returned `deny` with `files.read.deny[0]`.
  - `aegis policy explain command "rm -rf /"` returned `deny` with `commands.deny[0]`.
  - `aegis policy explain network api.github.com` returned `allow` with `network.allow[0]`.
- `aegis run --policy policies/strict.yaml -- echo hello` passed and replay for the session showed `policy_loaded`.
- `aegis replay --session last --verify` passed with `Hash chain: verified`.
- Invalid policy smoke test returned non-zero with `UnsupportedPolicyMode`.
- Phase 07 remains policy evaluation only. It does not enforce filesystem, command, network, environment, MCP, sandbox, or approval decisions yet.
- CI-mode ask decisions are converted to deny inside the evaluator so policy evaluation never waits for interactive input.

## Review Fixes

- [x] Fixed policy discovery so optional workspace/user policy locations fall through only on `FileNotFound`; unreadable, malformed, or otherwise unloadable discovered policies now fail closed.
- [x] Fixed JSON parsing to reject unknown top-level and nested policy keys, including misspelled rule keys like `denny` or `defualt`.
- [x] Added regression tests for non-missing workspace policy load failures and unknown JSON keys.
- [x] Removed generated `.aegis` runtime state from the worktree and ignored `.aegis/last`, `.aegis/last.tmp`, and `.aegis/sessions/`.

# Phase 08 Environment and Secret Protection Plan

## Assumptions

- Phase 08 owns environment filtering for direct children launched by `aegis run` and reusable redaction before audit persistence. It must not implement filesystem, command, network, MCP, keychain, password-manager, cloud credential, or future brokered secret features.
- Strict and CI mode should default to a minimal safe environment and fail closed when `--inherit-env` is requested without policy support.
- Observe and trusted modes may inherit environment according to policy, but audit persistence and replay output must still redact secret-like names and values.
- Policy `env.allow` and `env.deny_patterns` are already in the Phase 07 schema; Phase 08 should enforce those through the policy evaluator rather than adding ad hoc CLI decisions.
- Tests must use only obvious fake synthetic secrets and must assert that raw fake values are absent from persisted audit files and replay output.

## Research Check

- [x] Read `CODEX_MASTER_PROMPT.md`, `CANONICAL_IMPLEMENTATION_DECISIONS.md`, `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, `PRODUCTION_READINESS_GATES.md`, and `08_ENV_AND_SECRET_PROTECTION.md`.
- [x] Verified `src/intercept/env.zig` is currently a stub and `src/core/supervisor.zig` launches children without custom environment filtering.
- [x] Verified `src/audit/writer.zig` persists events through `src/audit/hash_chain.zig`, where target/decision string redaction currently uses a minimal bridge.
- [x] Verified policy env parsing already supports `inherit`, `allow`, `deny_patterns`, `ask`, and `default`, but built-in deny patterns need expansion for Phase 08.

## Checklist

- [x] Add tests first for secret-like env names, env allowlist, env deny patterns, strict/CI no-secrets behavior, `--no-secrets`, `--inherit-env` policy restrictions, secret value detection, stable redaction fingerprints, audit redaction events, persistence redaction, and replay redaction.
- [x] Implement reusable secret detection and redaction with stable SHA-256 fingerprints in the audit layer.
- [x] Implement policy-driven environment filtering in `src/intercept/env.zig`.
- [x] Wire filtered environments and redaction events into the supervisor/run/audit path without persisting raw secret values.
- [x] Add `aegis run --no-secrets` and guarded `aegis run --inherit-env`.
- [x] Expand built-in and checked-in policy deny patterns for common secret variable names.
- [x] Update run help text and keep capability claims bounded to Phase 08.
- [x] Run `zig build`, `zig build test`, and the requested manual smokes.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual `FAKE_GITHUB_TOKEN=fake_secret_value aegis run --no-secrets -- /usr/bin/env` passed: child output did not contain `FAKE_GITHUB_TOKEN` or `fake_secret_value`; audit files and replay output did not contain `fake_secret_value`; `secret_redacted` was present; `replay --verify` reported `Hash chain: verified`.
- Manual strict-mode smoke passed: `OPENAI_API_KEY=fake_secret_value GITHUB_TOKEN=fake_secret_value aegis run --mode strict -- /usr/bin/env` did not expose those variables to the child and did not persist `fake_secret_value`.
- Manual observe-policy smoke passed: `FAKE_GITHUB_TOKEN=fake_secret_value aegis run --policy policies/observe.yaml -- /usr/bin/env` inherited the fake variable to the child but audit files and replay output did not contain `fake_secret_value`.
- Manual policy smoke passed: a temp policy with `env.allow: SAFE_PHASE08` and `env.deny_patterns: FAKE_*` exposed `SAFE_PHASE08=visible`, stripped `FAKE_DENIED=hidden`, and did not persist `hidden`.
- Manual `--inherit-env` smoke passed: strict policy rejected it with a non-zero exit and explicit error, while a temp trusted policy with `env.inherit: true` inherited safe variables and still respected `env.deny_patterns`.
- Review fix: high-entropy redaction no longer flags path-shaped values such as local workspace paths, avoiding noisy false positives in audit events.

## Known Limitations

- Environment filtering is direct-child wrapper-level enforcement through `std.process.Child.env_map`; it is not OS-level process-tree containment.
- Observe policy can still pass fake secrets to the child by design, but audit and replay persistence redact them.
- Redaction heuristics are intentionally conservative and pattern-based; they may miss unknown secret formats or redact some non-secret token-shaped values.
- No keychain, 1Password, Bitwarden, cloud credential broker, or secret injection flow was added in this phase.

## Security Notes

- Raw synthetic secret values are redacted before event serialization, hash-chain calculation, JSONL write, summary write, and replay display.
- `secret_redacted` events store env names and stable SHA-256 fingerprints only; they do not store raw values.
- Strict, CI, and redteam modes force no-secrets behavior by default.
- `--inherit-env` fails closed unless `env.inherit: true` is present in the selected policy.

## Review Fixes

- [x] Fixed embedded secret assignments in command targets so joined `process_launch` command strings are redacted before JSONL persistence.
- [x] Fixed observe-mode overrides so policies with `env.inherit: false` keep minimal allowlist-only environments.
- [x] Added regression tests for both review findings and updated `tasks/lessons.md`.
