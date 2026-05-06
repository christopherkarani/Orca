# Phase 13 Red-team Benchmark Suite Plan

## Assumptions

- Phase 13 is limited to deterministic local red-team fixtures, fixture parsing/discovery, runner/reporting, scorecards, CLI integration, tests, and fixture documentation.
- Fixtures must exercise already implemented Aegis decision/audit/replay behavior through the policy, intercept, MCP, command, network, filesystem, and audit modules. They must not claim transparent OS-level enforcement unless the backend actually provides it.
- Fixtures will use synthetic local inputs and fake secrets only, run in temporary directories, avoid real home secret paths and external network calls, and verify that raw fake secret values are absent from `events.jsonl` and replay output.
- CI mode is non-interactive: ask decisions are treated as deny through the existing policy/guard behavior.

## Research Check

- [x] Read Phase 13 and the required canonical, architecture, security, and production-readiness documents.
- [x] Reviewed prior project task notes and lessons for redaction, CI ask-to-deny, command guard, MCP, filesystem, and network constraints.
- [x] Inspect existing redteam stubs, CLI wiring, audit/replay APIs, intercept APIs, and tests before implementation.
- [x] Validate which fixture expectations can be backed by current implemented controls and mark unsupported capabilities honestly.

## Checklist

- [x] Add tests first for fixture parsing, invalid validation, discovery, score calculation, category grouping, JSON output, passing/failing fixture execution, forbidden log content detection, CI exit behavior, temporary directory isolation, and fake-secret absence in audit/replay output.
- [x] Implement fixture format parsing and validation with bounded local-only YAML support.
- [x] Implement fixture discovery for category directories, direct fixture directories, and `--fixture` selection.
- [x] Implement deterministic runner that executes fixture commands in temporary directories and observes actual Aegis decisions/events/replay summaries.
- [x] Implement scorecard totals, category grouping, human output, JSON output, skipped/unsupported status, and CI exit semantics.
- [x] Wire `aegis redteam`, path selection, `--json`, `--ci`, and `--fixture`.
- [x] Add at least ten deterministic fixtures across prompt-injection, secret-exfil, mcp-tool-poisoning, network-exfil, shell-abuse, and filesystem-bypass.
- [x] Add docs for adding fixtures and limitations.
- [x] Run `zig build`, `zig build test`, `aegis redteam`, `aegis redteam --json`, and `aegis redteam --ci`.
- [x] Manually verify fixture count, category grouping, intentional CI failure behavior, fake-secret absence in `events.jsonl`, fake-secret absence in replay output, and readable human output.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- `zig-out/bin/aegis redteam` passed: 10/10 fixtures, 100%.
- `zig-out/bin/aegis redteam --json` emitted valid machine-readable JSON.
- `zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures and exit code 0.
- `zig-out/bin/aegis redteam fixtures/secret-exfil` passed with 2/2 fixtures.
- `zig-out/bin/aegis redteam --fixture secret-env-read-basic` passed with 1/1 fixtures.
- Manual discovery check found 10 `fixture.yaml` files.
- Manual CI regression check with a temporary intentionally failing fixture returned exit code 6.
- JSON report verification confirmed forbidden synthetic values were absent: `fake-secret-value`, `sk-fakeSyntheticOpenAIKey`, `OPENSSH PRIVATE`, and `PRIVATE KEY`.
- Review fix: replaced `std.testing.tmpDir` in the user-facing redteam runner with a fallible OS-temp helper, added regression coverage, and verified `aegis redteam` works from `/` with an absolute fixture path.
- Red-team fixtures exercise current implemented controls: policy/intercept decisions, command classification, network decision heuristics, MCP metadata/tool evaluation, filesystem normalization/symlink escape detection, audit writer, and replay rendering.
- Known limitation: filesystem and network fixtures prove Aegis-mediated decision/audit behavior; they do not claim transparent OS-level child-process file or socket interception.
