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

- [x] Enforce critical/high tool metadata findings during later `tools/call`, not only during `tools/list` audit.
- [x] Forward JSON-RPC notifications without waiting for server responses, including `notifications/initialized`.
- [x] Make `aegis mcp inspect` send `notifications/initialized` before `tools/list`.
- [x] Preserve multi-token server argv passed with `--command ... -- ...`.
- [x] Add regression tests and update fake fixtures for compliant initialization and metadata enforcement.
- [x] Re-run `zig build`, `zig build test`, and focused MCP smokes.

## Review Fix Results

- `zig build` passed.
- `zig build test` passed.
- Added regression coverage for notification pass-through, metadata-gated denial of safe-looking `search_*` tools, and multi-token `--command` parsing.
- Updated the fake MCP server to require `notifications/initialized` before `tools/list`; `aegis mcp inspect --command fixtures/mcp/fake_server.py` and `aegis mcp inspect --command python3 -- fixtures/mcp/fake_server.py` both passed.
- Verified `notifications/initialized` does not produce proxy stdout and does not block the next request.
- Verified `search_admin_secret` is denied with `MCP tool call denied by flagged metadata` even though default policy allows `*.search_*`.
- Re-ran invalid JSON-RPC, oversized message, fake-secret redaction, protocol-clean stdout, and replay verification smokes.

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

# Phase 11 MCP Stdio Proxy Plan

# Phase 12 Network Egress Guard Plan

## Assumptions

- Phase 12 owns network policy decision logic, destination parsing/matching, exfiltration heuristics, audit events, CLI run-time overlays, child environment metadata hooks, and honest capability reporting.
- Transparent network enforcement is not universally implemented in this phase. Direct Aegis decisions and child environment metadata hooks may be active, while proxy-mediated and OS-level transparent enforcement remain deferred to platform backend phases unless a managed proxy is actually started later.
- Network policy should extend the existing policy schema without breaking Phase 07 policy files: `network.mode`, `network.detect_exfiltration`, and current `allow`/`ask`/`deny` rules must all parse.
- Tests must use synthetic destinations and local safe commands only. No test may require external network access or persist raw fake secrets.

## Research Check

- [x] Read `CODEX_MASTER_PROMPT.md`, `CANONICAL_IMPLEMENTATION_DECISIONS.md`, `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, `PRODUCTION_READINESS_GATES.md`, and `12_NETWORK_EGRESS_GUARD.md`.
- [x] Verified `src/intercept/network.zig` is currently a stub and policy network evaluation only matches raw host strings.
- [x] Verified audit persistence redacts target values and decision reasons through `audit/redact_bridge.zig`, but Phase 12 needs URL-aware redaction before network event persistence.
- [x] Verified `aegis run` already has policy/env/command guard hooks where run-time network overlays and child environment metadata can be installed.

## Checklist

- [x] Add tests first for exact/wildcard/IP/local/private/metadata matching, deny priority, strict/CI ask behavior, network modes, exfiltration heuristics, URL redaction, CLI overlays, network audit/replay, and doctor output.
- [x] Implement `src/intercept/network.zig` as a pure testable decision engine with destination parsing, host/IP classification, policy matching, exfiltration scoring, and redacted audit target helpers.
- [x] Extend policy schema/loading/presets/explain for `network.mode` and `network.detect_exfiltration` while preserving existing policy compatibility.
- [x] Wire `aegis run` flags: `--no-network`, `--allow-network <domain>`, and `--network observe|ask|allowlist|open|off`.
- [x] Add bounded child environment metadata hooks without claiming active proxy or OS-level transparent enforcement.
- [x] Emit network audit events for configured allow rules, deny rules, exfiltration suspicion, and temporary run-time allow rules, with redaction before persistence.
- [x] Update `aegis doctor` capability rows to distinguish policy engine, observation, transparent enforcement, and proxy-mediated enforcement honestly.
- [x] Run `zig build`, `zig build test`, and required manual verification commands.
- [x] Document review results, known limitations, security notes, and acceptance criteria status.

## Review

- `zig build test` passed.
- `zig build` passed.
- Manual `aegis run --workspace <tmp> --no-network -- true` passed and wrote `network_connect_denied` events with `network mode off`.
- Manual `aegis run --workspace <tmp> --allow-network api.github.com -- true` passed and wrote replayable `network_connect_allowed` events for `api.github.com`.
- Manual `aegis policy explain network api.github.com` returned `allow` via `network.allow[0]`.
- Manual `aegis policy explain network pastebin.com` returned `deny` via `network.deny[0]` with paste-site exfiltration risk.
- Manual `aegis doctor` reported:
  - network policy engine: active
  - network observation: partial
  - transparent network enforcement: unavailable
  - proxy-mediated enforcement: unavailable
- Manual replay verification passed for sessions with generated network events.
- Manual synthetic secret URL smoke confirmed the fake `sk-fakeSyntheticOpenAIKey...` value did not appear in `events.jsonl` or replay output.

## Known Limitations

- Phase 12 does not implement universal transparent OS-level network enforcement. `aegis doctor` reports transparent network enforcement as unavailable.
- Proxy-mediated enforcement is unavailable in this phase because no managed local proxy is started.
- Network audit events are emitted for Aegis-mediated policy decisions and configured run-time network rules, not for every socket opened by arbitrary child processes.

## Security Notes

- Deny rules beat allow rules.
- CI mode converts ask decisions to deny and never prompts.
- Direct IP, localhost, private network, and cloud metadata destinations deny by default unless explicitly allowed.
- URL targets are redacted before persistence; synthetic secret URL values were checked against both `events.jsonl` and replay output.

## Review Fixes

- [x] Fixed capability reporting so proxy-mediated network enforcement is `unavailable` unless a managed proxy is actually started. Child env metadata now reports `AEGIS_PROXY_MEDIATED_NETWORK_ENFORCEMENT=unavailable`.
- [x] Fixed core policy API network evaluation to preserve `NetworkAction.scheme` and `NetworkAction.port` when constructing the destination for policy matching.
- [x] Fixed `UnknownDomainTracker` to duplicate host keys on insert and free owned keys on deinit.
- [x] Added regression tests for scheme/port network matching and owned unknown-domain tracker keys.
- [x] Re-ran `zig build test`, `zig build`, and `aegis doctor` network capability smoke.

## Assumptions

- Phase 11 is stdio-only MCP proxying: no remote HTTP MCP, OAuth, hosted gateway, resources/prompts/sampling enforcement beyond pass-through logging for unknown methods.
- Stdio MCP protocol traffic is newline-delimited UTF-8 JSON-RPC. The proxy must reject oversized, invalid, or embedded-newline messages for the affected action.
- `aegis mcp proxy` must reserve stdout for JSON-RPC only; diagnostics, server stderr, and human/debug logs go to stderr or audit files.
- MCP tool-call decisions must use the existing policy evaluator. Server-scoped policy config can be flattened to existing `server.tool` MCP selectors.
- Persistent MCP audit events must use the existing audit writer and redaction path; tool arguments are stored only as bounded/redacted target strings.
- Interactive ask approvals are supported only when not in CI mode and when the proxy has a prompt-capable stderr/stdin path; CI converts ask to deny.

## Research Check

- [x] Read `CODEX_MASTER_PROMPT.md`, `CANONICAL_IMPLEMENTATION_DECISIONS.md`, `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, `PRODUCTION_READINESS_GATES.md`, and `11_MCP_STDIO_PROXY.md`.
- [x] Verified `src/mcp/jsonrpc.zig`, `src/mcp/stdio.zig`, `src/mcp/proxy.zig`, and `src/mcp/tools.zig` are placeholders.
- [x] Verified MCP policy evaluation already exists as flat selectors via `policy.evaluate` and needs server-scoped YAML/JSON parsing support for the Phase 11 policy shape.
- [x] Verified audit persistence goes through `src/audit/writer.zig` and target/decision fields are redacted by `src/audit/redact_bridge.zig`.

## Checklist

- [x] Add Phase 11 tests first for JSON-RPC framing, invalid/oversized input, metadata scanning, policy shape parsing, and proxy behavior.
- [x] Add fake stdio MCP server/client fixtures for smoke tests.
- [x] Implement bounded JSON-RPC line parser/writer with no embedded-newline acceptance.
- [x] Implement MCP tool metadata extraction, schema limits, risk classification, and suspicious metadata findings.
- [x] Implement stdio server subprocess proxying for `initialize`, `tools/list`, `tools/call`, and pass-through unknown methods.
- [x] Enforce `tools/call` through existing policy evaluation, including matched rule reporting and CI ask-to-deny behavior.
- [x] Integrate approval request events and user approval/denial events without waiting in CI.
- [x] Emit MCP audit events through the audit writer with secret-like arguments redacted before persistence.
- [x] Implement `aegis mcp inspect --command <server>` and `aegis mcp proxy --command <server>`.
- [x] Update help text without claiming future HTTP/OAuth behavior.
- [x] Run `zig build`, `zig build test`, and manual MCP smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual `aegis mcp inspect --command fixtures/mcp/fake_server.py` passed and listed safe, write, delete, and malicious tools with findings.
- Manual `fixtures/mcp/fake_client.py | aegis mcp proxy --command fixtures/mcp/fake_server.py` passed: `initialize`, `tools/list`, and safe `search_issues` forwarded; `delete_repository` returned a JSON-RPC policy error.
- Manual invalid JSON-RPC input returned a valid JSON-RPC error response with `id: null`.
- Manual oversized MCP input returned a valid JSON-RPC error response with code `-32002`.
- Manual secret argument smoke confirmed `fake_secret_value` does not appear in `.aegis/sessions/**/events.jsonl`; MCP audit target values are redacted with stable fingerprints.
- Manual replay passed with MCP events visible and `Hash chain: verified`.
- Protocol stdout validation passed for proxy, invalid, secret-argument, and oversized smokes; server stderr logs stayed on stderr.
- Non-CI `ask` decisions now use a best-effort `/dev/tty` approval channel so MCP protocol stdin remains reserved for JSON-RPC; if no TTY is available, ask fails closed.
- Phase 11 remains stdio-only. Remote HTTP MCP, OAuth, hosted gateway behavior, and full resources/prompts/sampling mediation remain out of scope for later phases.

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

# Phase 09 Filesystem Guard and Staged Writes Plan

## Assumptions

- Phase 09 implements the filesystem decision engine and staged-write workflow for Aegis-controlled operations only. It must not claim transparent OS-level interception of arbitrary child-process file IO.
- Filesystem read/write decisions should route through the existing policy evaluator and include matched-rule explanations where available, with default protected-path behavior supplementing policy defaults.
- Staged writes live under `.aegis/sessions/<session-id>/` and must remain reviewable through `aegis diff`, `aegis apply`, and `aegis discard`.
- Persistent file/staging audit events must go through the existing audit writer and redaction bridge before storage.
- Strict/CI ambiguity should fail closed for path decisions, especially traversal, symlink escape, missing workspace context, and invalid policy state.

## Research Check

- [x] Read `CODEX_MASTER_PROMPT.md`, `CODEX_AGENT_CONTEXT.md`, `CANONICAL_IMPLEMENTATION_DECISIONS.md`, `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, `PRODUCTION_READINESS_GATES.md`, and `09_FILESYSTEM_GUARD_AND_STAGING.md`.
- [x] Reviewed existing Phase 04-08 task notes and lessons for CLI exit behavior, audit failure handling, policy fail-closed behavior, and redaction persistence.
- [x] Verify current CLI diff/apply/discard placeholders, build test registration, policy action shape, audit event model, and session layout before implementation.

## Checklist

- [x] Add tests first for relative/absolute path normalization, workspace containment, traversal escape, symlink escape, `.env`, fake `~/.ssh/id_ed25519`, staged create/update, diff/apply/discard, staging index integrity, and audit events.
- [x] Implement filesystem path normalization and containment checks in `src/intercept/files.zig`.
- [x] Implement file read/write policy evaluation and default sensitive read/protected write rules without ad hoc CLI-only decisions.
- [x] Implement staged write storage under `.aegis/sessions/<session-id>/staged/`, `original/`, and `staging-index.json`.
- [x] Implement diff/apply/discard core operations with original-state verification where feasible.
- [x] Wire `aegis diff`, `aegis apply`, and `aegis discard` to the staging engine, including `--session last` and `--file <path>`.
- [x] Emit filesystem audit events through the existing redacted audit persistence path.
- [x] Update help/docs only as needed, with honest Aegis-mediated coverage limits.
- [x] Run `zig build`, `zig build test`, and required manual Phase 09 smoke checks.
- [x] Document review results, known limitations, security notes, and acceptance criteria status.

## Review

- `zig build --summary all` passed.
- `zig build test --summary all` passed with 85/85 tests.
- Manual staged apply smoke passed:
  - Created an Aegis-mediated staged file in session `2026-05-06T20-23-24Z_4c40`.
  - Verified `.aegis/sessions/2026-05-06T20-23-24Z_4c40/staging-index.json` existed before apply.
  - `aegis diff --session last` showed the staged create diff.
  - `aegis apply --session last` applied the staged file.
  - `aegis replay --session last --verify` showed `file_write_attempt`, `file_write_staged`, and `file_apply`, with hash-chain verification passing.
- Manual staged discard smoke passed:
  - Created an Aegis-mediated staged file in session `2026-05-06T20-23-31Z_a8f3`.
  - Verified `.aegis/sessions/2026-05-06T20-23-31Z_a8f3/staging-index.json` existed before discard.
  - `aegis discard --session last` discarded the staged file without creating it in the workspace.
  - `aegis replay --session last --verify` showed `file_write_attempt`, `file_write_staged`, and `file_discard`, with hash-chain verification passing.
- Manual symlink escape smoke passed with `SymlinkEscapesWorkspace`.
- Phase 09 implements the filesystem decision engine and staged-write workflow for Aegis-mediated operations. It does not claim transparent OS-level interception of arbitrary child-process file IO.
- Unicode normalization is documented as a limitation of this phase; paths are UTF-8 validated and separator/case handling is conservative.

## Review Fixes

- [x] Fix builtin home-directory read denies so workspace-at-home paths like `.ssh/config` still match `~/.ssh/**`.
- [x] Verify `staged_hash` before applying create/update entries so reviewed staged bytes cannot be swapped before apply.
- [x] Generate diffs against the captured `original/` copy for update/delete entries instead of live workspace contents.
- [x] Add regression tests for all three review findings.
- [x] Re-run `zig build` and `zig build test`.

# Phase 10 Command Guard and Approvals Plan

## Assumptions

- Phase 10 owns command classification, command decision enforcement for Aegis-mediated execution, interactive/session approvals, audit events, and initial PATH shims only. It must not claim full OS-level or process-tree interception.
- Command parsing should be pragmatic and token-aware enough for high-signal dangerous patterns, not a complete shell parser.
- Command decisions must route through `policy.evaluate` and persistent events must use the existing audit writer/redaction path.
- CI mode must convert every ask outcome to deny and must never read from stdin.
- Shims should be session-local under `.aegis/sessions/<session-id>/shims/`, cover a small practical command set first, and avoid recursion by resolving the real binary with the shim directory removed from `PATH`.

## Research Check

- [x] Read `CODEX_MASTER_PROMPT.md`, `CANONICAL_IMPLEMENTATION_DECISIONS.md`, `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, `PRODUCTION_READINESS_GATES.md`, and `10_COMMAND_GUARD_AND_APPROVALS.md`.
- [x] Reviewed existing policy evaluation, audit writer/redaction, event schema, run supervision, and current intercept command/approval stubs.
- [x] Checked existing lessons for audit/redaction, fail-closed policy behavior, and runtime artifact handling.

## Checklist

- [x] Add tests first for command classification, policy decisions, CI ask denial, session approval, audit redaction, run integration, and shim callback behavior.
- [x] Implement command risk classes, bounded command display, tokenization, high-risk pattern matching, and risk scoring in `src/intercept/commands.zig`.
- [x] Implement approval session state and interactive prompt handling in `src/intercept/approvals.zig`.
- [x] Wire command evaluation through the existing policy engine with deny priority, risk-backed decisions, and matched-rule preservation.
- [x] Emit command attempt/allowed/denied/approval/user decision events through the audit path without persisting child stdout/stderr.
- [x] Integrate command guard into `aegis run` before child launch and make denied commands return non-zero.
- [x] Add `aegis shim exec -- <command> [args...]`, create session shim directories, prepend PATH only inside the Aegis session, and generate a small safe shim set.
- [x] Update help and task review notes with honest wrapper/shim coverage limitations.
- [x] Run `zig build`, `zig build test`, and all requested manual smoke checks.
- [x] Document review results, known limitations, security notes, and acceptance criteria status.

## Review

- `zig build --summary all` passed.
- `zig build test --summary all` passed with 100/100 tests.
- Manual CI smoke passed: `aegis run --workspace /tmp/aegis-phase10.F5pjLB --mode ci -- npm install left-pad` returned exit code `3` without prompting.
- Manual safe command smoke passed: `aegis run --workspace /tmp/aegis-phase10.F5pjLB -- true` returned exit code `0`.
- Manual dangerous command smoke passed: `aegis run --workspace /tmp/aegis-phase10.F5pjLB -- rm -rf /` returned exit code `3`.
- Manual replay smoke passed with command decision events and `Hash chain: verified`.
- Manual fake-secret smoke passed: `OPENAI_API_KEY=sk-fakeSyntheticOpenAIKey1234567890` did not appear raw in session audit files.
- Manual PATH shim directory smoke passed: the session contained shims for `bash`, `curl`, `git`, `node`, `npm`, `pip`, `pnpm`, `python`, `sh`, `wget`, `yarn`, and `zsh`.
- Manual shim callback smoke passed: `aegis shim exec -- git status` delegated to the real `git`, and `aegis shim exec -- rm -rf /` returned exit code `3` with command denial events.

## Known Limitations

- Command parsing is pragmatic and pattern-based; it intentionally is not a complete shell parser.
- Command Guard protects Aegis-mediated direct execution and wrapper/PATH-shim callbacks. It does not claim full OS-level or process-tree interception.
- The initial direct child command is policy-checked before launch; PATH shims are best-effort wrapper infrastructure for commands resolved inside the Aegis session environment.
- The initial shim set is small and POSIX-shell oriented. Windows-specific `.cmd`/PowerShell shim coverage is left for later platform phases.
- Non-interactive ask decisions outside CI are denied instead of prompting to avoid hangs.

## Security Notes

- Deny decisions beat allow for mandatory high-risk classifier findings.
- CI mode never prompts; ask decisions become deny.
- Command audit events go through the existing redacting audit writer and do not persist raw child stdout/stderr.
- Shim delegation removes the session shim directory from `PATH` before resolving the real binary to avoid recursive shim invocation.
- Command strings are bounded before evaluation/logging, and serialized audit target/decision fields remain redacted.

## Review Fixes

- [x] Added the new `src/cli/shim.zig` module to the visible patch with intent-to-add so clean-checkout reviews include it.
- [x] Preserved parent approvals across shim callbacks using SHA-256 command approval hashes, with one-time approvals consumed before real-binary delegation.
- [x] Expanded shim coverage for risky aliases recognized by the classifier, including `pip3`, `python3`, `ssh`, `scp`, `nc`, `netcat`, `powershell`, and `pwsh`.
- [x] Added regression tests for approved ask-class shim delegation, approval hash redaction, and risky alias shim coverage.
- [x] Re-ran `zig build` and `zig build test`, plus focused shim manual smokes.
