# Phase 17 Advanced MCP and Server Manifests Plan

## Assumptions

- Phase 17 is limited to MCP v1.0 firewall hardening: manifests, resource/prompt/sampling mediation, CLI helpers, redaction, and transport abstraction groundwork.
- Existing stdio MCP proxy behavior from Phase 11 must remain compatible for `initialize`, `notifications/initialized`, `tools/list`, and allowed `tools/call`.
- Remote/HTTP MCP should be represented by bounded interfaces and honest limited/deferred status unless a small implementation can be completed without weakening stdio or adding network dependencies.
- Manifest defaults may influence decisions, but explicit policy deny still wins and manifest data is never a security bypass.
- Tests must use fake MCP servers, fake secrets, and local files only; no external network and no credentials.

## Research Check

- [x] Read Phase 17 and required canonical, architecture, security, production gates, dependency matrix, project lessons, and relevant memory.
- [x] Inspect current MCP proxy, manifest placeholders, schema limits, tools, resources, prompts, sampling, and transport modules.
- [x] Inspect policy schema/evaluation for MCP action support and deny precedence.
- [x] Inspect audit writer/replay/redaction path to confirm redaction-before-persistence behavior for MCP payloads.
- [x] Inspect CLI `mcp` routing and existing tests/build wiring.
- [x] Validate false-positive risks before broad edits: stdio stdout must stay protocol-only, CI ask must deny, generated manifests must not print env values, and oversized payload handling must remain fail-safe.

## Checklist

- [x] Capture baseline verification before implementation.
- [x] Add failing or focused tests for manifest parsing/validation and policy precedence.
- [x] Implement MCP manifest model, bounded parser, validation, and starter generation without raw secrets.
- [x] Wire manifest defaults into MCP tool/resource/prompt/sampling policy decisions while preserving explicit deny priority.
- [x] Implement resource controls for `resources/list` logging and `resources/read` mediation, sensitive URI classification, response bounds, and redacted audit payloads.
- [x] Implement prompt controls for `prompts/list` logging and `prompts/get` mediation, bounded/redacted prompt audit data, and CI non-interactive behavior.
- [x] Implement sampling controls with default deny, ask/allow/deny support, CI ask-to-deny, security-sensitive audit events, bounded/redacted arguments, and valid JSON-RPC denial errors.
- [x] Improve MCP redaction coverage for tools/resources/prompts/sampling and replay output.
- [x] Extend CLI commands: `aegis mcp list`, `aegis mcp trust`, `aegis mcp manifest check`, and `aegis mcp manifest generate`.
- [x] Add or refine transport abstraction for stdio plus explicit future HTTP stubs/status.
- [x] Add fake MCP fixtures/tests covering resources, prompts, sampling, manifest CLI, transport compatibility, invalid/oversized messages, and fake-secret non-persistence.
- [x] Run required verification: `zig build`, `zig build test`, `./zig-out/bin/aegis redteam --ci`.
- [x] Run manual MCP smokes requested in Phase 17.
- [x] Document review results, MCP feature support status, remote/HTTP status, security notes, and acceptance criteria status.
- [x] Review fix: bind manifests to launched MCP command, args, expected hash, and env allowlist.
- [x] Review fix: mediate server-originated sampling requests.
- [x] Review fix verification: rerun required builds, tests, redteam, and targeted MCP smokes.

## Review

- Baseline verification before Phase 17 changes: `zig build` passed.
- Baseline verification before Phase 17 changes: `zig build test` passed.
- Existing MCP state: stdio framing and tool mediation exist; manifests, resources, prompts, and sampling modules were placeholders.
- Existing policy state: MCP tool/resource/prompt/sampling action variants exist and use a shared MCP selector ruleset; deny precedence and CI ask-to-deny already exist in policy evaluation.
- Existing CLI state: `aegis mcp` only supported `inspect` and `proxy`; Phase 17 commands need new routing.
- Implemented manifest parser/validator for the Phase 17 YAML shape, including server metadata, env allowlist, per-tool risk/default, resource default, prompt default, and sampling default.
- Implemented manifest influence for tools/resources/prompts/sampling while preserving explicit policy deny precedence.
- Implemented `resources/list`, `resources/read`, `prompts/list`, `prompts/get`, and `sampling/createMessage` proxy handling.
- Sampling defaults to deny; CI converts ask to deny and never prompts.
- Sensitive resource URIs are treated as sensitive by default unless explicitly allowed by policy.
- Added `aegis mcp list`, `aegis mcp trust`, `aegis mcp manifest check`, and `aegis mcp manifest generate`.
- Added stdio transport descriptors and an explicit HTTP transport stub returning `HttpMcpTransportDeferred`; remote/HTTP MCP remains limited/deferred.
- Updated fake MCP fixtures to exercise resources, prompts, sampling, and fake secrets.
- Added `docs/dev/mcp-phase17.md` with supported/deferred MCP status.
- Final verification: `zig build` passed.
- Final verification: `zig build test` passed.
- Final verification: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- Manual smoke: valid manifest check succeeded; invalid manifest check failed clearly with `UnsupportedRisk`.
- Manual smoke: generated manifest omitted a fake GitHub token and passed manifest check.
- Manual smoke: `aegis mcp list` discovered a local `.aegis/mcp/*.yaml` manifest.
- Manual smoke: `aegis mcp trust fake --tool search_issues` printed a safe policy snippet instead of mutating config.
- Manual smoke: fake MCP server resource reads and prompt gets were mediated; sampling was denied by default.
- Manual smoke: proxy stdout contained only parseable JSON-RPC protocol lines.
- Manual smoke: replay showed resource, prompt, and sampling events.
- Manual smoke: fake secrets from MCP arguments/resources/prompts did not appear in `events.jsonl` or replay output.
- Known limitation: remote/HTTP MCP is not production-implemented in Phase 17; only the interface/stub and status documentation are present.
- Known limitation: prompt/resource response bodies are not persisted by default; audit records bounded redacted event targets and decisions.
- Known limitation: MCP policy uses the existing selector model (`server.name`, `server.uri`, `server.model`) rather than a separate nested resource/prompt/sampling policy schema.
- Review correction opened two P1 gaps: server-originated sampling was not mediated, and manifest defaults were not bound tightly enough to the launched process.
- Review fix: manifest defaults now require exact command/args match, optional expected SHA-256 match, and a manifest-derived environment allowlist before the server is spawned.
- Review fix: when a server emits `sampling/createMessage` while Aegis is waiting for a response, Aegis evaluates policy/manifest controls, sends denied sampling JSON-RPC errors back to the server by default, and only forwards to the client when explicitly allowed.
- Review fix verification: `zig build` passed.
- Review fix verification: `zig build test` passed.
- Review fix verification: `./zig-out/bin/aegis redteam --ci` passed with 10/10 fixtures.
- Targeted smoke: bound manifest proxy with expected hash produced protocol-clean JSON-RPC output.
- Targeted smoke: mismatched launched command with a manifest failed with `ManifestCommandMismatch` and exit code 2.
