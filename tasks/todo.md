# Phase 20 Security Hardening and Fuzzing Plan

## Assumptions

- Phase 20 is limited to hardening existing security-sensitive surfaces and documenting actual capability limits.
- This phase must not add SaaS, hosted dashboards, monetization, enterprise sync, default telemetry, formal verification, or major new product features.
- No real secrets, external network services, real LLM calls, or user credential paths may be required by tests.
- Zig-native fuzzing may not be practical on the pinned toolchain; deterministic mutation tests under `tests/fuzz/` are acceptable if exposed through `zig build fuzz`.
- Documentation must describe wrapper-only, partial, active, and unsupported protections honestly.

## Research Check

- [x] Read required Phase 20 context files and project lessons.
- [x] Baseline current `zig build test` before adding regression tests.
- [x] Inventory existing path, policy, command, MCP, redaction, network, audit, red-team, and docs coverage.
- [x] Re-check assumptions after adding tests to identify false positives, gaps, and overclaims.

## TDD Checklist

- [x] Add or improve path regression tests for traversal, absolute escapes, symlink escapes, hardlink feasibility, case matching, Unicode normalization edge cases, Windows drive/UNC/backslash forms, protected `.env`, `~/.ssh/**`, cloud credential paths, browser profile paths, shell-sensitive names, temp rename patterns, spaces, and workspace containment.
- [x] Add or improve command classification tests for chaining, pipes, redirects, subshells, command substitution, encoded commands, PowerShell encoded flags, `Invoke-WebRequest/iwr/irm | iex`, `curl|sh`, `wget -O-|bash`, base64 decode into shell, destructive/privilege/git/credential commands, whitespace/quote tricks, and fake secrets embedded in command text.
- [x] Add or improve MCP malformed-input and mediation tests for invalid/oversized/newline/deep messages, malformed IDs, unexpected methods, high-volume `tools/list`, malicious descriptions, suspicious schemas, secret-like arguments, resource/prompt redaction, sampling default-deny, JSON-RPC error responses, and stdout protocol cleanliness.
- [x] Add or improve policy parser tests for valid and invalid policies, unknown modes, missing version, invalid rule shapes, malformed glob patterns, deny priority, CI ask-to-deny, strict/ci fail-closed behavior, matched-rule explanations, built-in presets, and every `policies/presets/*.yaml` file.
- [x] Add or improve secret redaction tests for synthetic env/API/cloud/JWT/PEM/high-entropy/URL/MCP/policy/command examples, stable fingerprints, and absence from persistent audit/replay/summary/red-team/doctor outputs.
- [x] Add or improve audit integrity tests for valid chains, modified/deleted/reordered events, changed previous/event hashes, summary/final-hash mismatch, replay verify non-zero on tamper, and redaction-before-persistence.
- [x] Add or improve network heuristic tests for exact/wildcard allow, deny priority, direct/localhost/private/metadata default deny, long query/base64/high-entropy/long subdomain/paste/webhook/tunnel signals, redacted URLs before audit, and invalid destination fail-closed behavior.
- [x] Add deterministic mutation/fuzz-style tests for policy parser, path normalizer, command classifier, MCP JSON-RPC parser, secret redactor, and network destination parser; expose them via `zig build fuzz`.
- [x] Implement only the hardening needed to make the tests pass, keeping changes behind existing APIs where possible.
- [x] Update/verify `SECURITY.md` and the requested security/platform docs with supported versions, disclosure process, threat model, limitations, red-team/security test commands, and no overclaims.

## Verification Checklist

- [x] `zig build`
- [x] `zig build test`
- [x] `zig build fuzz`
- [x] `./zig-out/bin/aegis redteam --ci`
- [x] `./zig-out/bin/aegis doctor`
- [x] `./zig-out/bin/aegis version --json`
- [x] Manual tamper test proves `aegis replay --verify` fails non-zero.
- [x] Red-team run/replay/log scan confirms synthetic secrets do not appear.
- [x] Validate every policy preset under `policies/presets/*.yaml`.
- [x] Run MCP malformed-input, path traversal/symlink, and command bypass tests through the security suite.
- [x] Scan generated policy, audit, replay, red-team, doctor, and release/install surfaces for raw synthetic secrets.
- [x] Check docs for unsupported enforcement overclaims.

## Review

- Baseline before hardening: `zig build test --summary all` passed with 207/213 tests passing and 6 skipped.
- Final gates: `zig build`, `zig build test`, `zig build fuzz`, `./zig-out/bin/aegis redteam --ci`, `./zig-out/bin/aegis doctor`, and `./zig-out/bin/aegis version --json` all passed.
- Final counted suites: `zig build test --summary all` passed with 225/231 tests passing and 6 skipped; `zig build fuzz --summary all` passed with 6/6 mutation tests.
- Manual tamper check in a temporary workspace changed an audit event target kind and `aegis replay --verify` exited 1 with `invalid event_hash`.
- Policy preset validation passed for every file under `policies/presets/*.yaml`.
- MCP malformed and oversized stdin smoke checks returned JSON-RPC error objects on stdout with no stderr human logs.
- Manual path, command, and network explain probes returned deny decisions for traversal/symlink, command-bypass, metadata endpoint, webhook, and high-entropy DNS cases.
- Raw synthetic secret scan found no fake secret values in `.aegis` audit artifacts, policies, red-team JSON output, doctor output, replay tamper output, or Phase 19 script/packaging surfaces.
- Documentation review found only explicit limitation wording for perfect sandboxing and transparent enforcement, not active overclaims.

Known limitations:

- Hardlink source provenance is not transparently enforceable without a stronger platform backend; Phase 20 adds protected-name coverage and documents the limitation.
- Network controls remain policy/observation and wrapper/proxy mediated unless `aegis doctor` reports an active platform backend.
- File controls remain staged-write/protected-path mediated unless a platform backend reports transparent file enforcement.
- MCP hardening covers stdio proxy mediation; remote HTTP MCP, OAuth, and hosted gateway behavior remain out of scope.

## Review Remediation

- [x] Add regression tests for shell-control command strings that must preserve argv mandatory-deny classifications.
- [x] Add regression tests proving literal bracketed policy paths validate and match literally.
- [x] Fix command classification without weakening shell-control heuristics.
- [x] Fix policy validation without allowing malformed or unsafe control characters.
- [x] Run focused and full verification after the fixes.

Review remediation results:

- Added failing-first tests for `find /tmp -delete > /tmp/log` and `shred /tmp/file > /tmp/log`; both now remain destructive mandatory-deny classifications.
- Added a policy regression proving `./src/routes/[id]/+page.svelte` and `./docs/[draft].md` validate and match literally.
- Replaced blanket bracket/brace rejection with control-character rejection, matching the current `*`/`?` wildcard semantics.
- Verification after remediation: `zig build`, `zig build test --summary all`, `zig build fuzz --summary all`, `./zig-out/bin/aegis redteam --ci`, `./zig-out/bin/aegis doctor`, `./zig-out/bin/aegis version --json`, and `git diff --check` all passed.
