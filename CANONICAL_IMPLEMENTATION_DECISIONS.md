# Canonical Implementation Decisions for Aegis v1.0

This document removes remaining ambiguity before implementation by Codex coding agents. Treat these decisions as binding unless a later human review intentionally changes them.

---

## 1. Canonical Source Layout

Use this source layout by v1.0. Early phases may create placeholders, but later phases should converge to this shape.

```text
src/
  main.zig
  cli/
    mod.zig
    args.zig
    exit_codes.zig
    help.zig
    run.zig
    init.zig
    doctor.zig
    policy.zig
    replay.zig
    diff.zig
    apply.zig
    discard.zig
    mcp.zig
    redteam.zig
    completions.zig
  core/
    mod.zig
    errors.zig
    types.zig
    time.zig
    platform.zig
    session.zig
    event.zig
    decision.zig
    supervisor.zig
    limits.zig
    util.zig
  policy/
    mod.zig
    schema.zig
    load.zig
    validate.zig
    compile.zig
    evaluate.zig
    explain.zig
    matchers.zig
    presets.zig
  audit/
    mod.zig
    writer.zig
    replay.zig
    hash_chain.zig
    summary.zig
    redact_bridge.zig
  intercept/
    mod.zig
    env.zig
    files.zig
    commands.zig
    network.zig
    approvals.zig
  mcp/
    mod.zig
    jsonrpc.zig
    transport.zig
    stdio.zig
    proxy.zig
    schema_limits.zig
    tools.zig
    resources.zig
    prompts.zig
    sampling.zig
    manifests.zig
  sandbox/
    mod.zig
    backend.zig
    observe.zig
    linux.zig
    macos.zig
    windows.zig
  redteam/
    mod.zig
    fixtures.zig
    runner.zig
    scorecard.zig
    reports.zig
```

If an earlier file path in a phase references `src/core/policy_engine.zig` or `src/core/audit.zig`, implement a forwarding module only if needed for compatibility, but the canonical production modules are `src/policy/` and `src/audit/`.

---

## 2. Canonical Build and Toolchain Rules

- Pin a Zig toolchain version in the repository once implementation begins.
- The exact version should be selected at implementation time based on the current stable Zig release and CI availability.
- Store the selected version in a visible place such as `.zigversion`, `README.md`, and CI workflow configuration.
- Do not silently rely on a developer's global Zig version.
- `zig build` and `zig build test` are the minimum commands every phase must keep working.

---

## 3. v1.0 Minimum Enforcement Baseline

Aegis v1.0 must provide these protections across all supported platforms:

1. **Environment filtering** for child processes.
2. **Secret redaction before persistent logging**.
3. **Policy evaluation and explanations** for all security-relevant actions.
4. **Tamper-evident audit logs** for every session.
5. **Staged-write workflow** for Aegis-mediated writes.
6. **Command risk classification and approval/deny behavior** through wrappers/shims and direct Aegis-mediated execution.
7. **Stdio MCP proxy enforcement** for MCP traffic that goes through Aegis.
8. **Network policy decision engine and at least proxy/wrapper-mediated enforcement hooks**.
9. **Honest platform capability reporting** for any transparent enforcement that is missing or partial.
10. **Deterministic red-team fixtures** that exercise the implemented controls.

Aegis v1.0 should additionally provide **stronger active OS-level enforcement on Linux where kernel features are available**. If a Linux system lacks required kernel features, Aegis must fall back safely and report the downgrade.

macOS and Windows v1.0 may be wrapper/partial backends, but they must not claim transparent enforcement unless it is actually implemented.

---

## 4. Process I/O Contract

By default, Aegis should stream child stdout/stderr to the user's terminal but should **not persist raw child stdout/stderr** to audit logs.

If a later feature captures child output:

- capture must be bounded;
- capture must pass through redaction before persistence;
- capture must be opt-in or clearly documented;
- tests must prove synthetic secrets in output are redacted.

Audit events should persist structured security events, not unbounded terminal transcripts.

---

## 5. Approval Contract

Any interactive approval must include:

- the requested action;
- the actor/process if known;
- the target;
- the matched policy/default;
- risk explanation;
- approval scope choices;
- safe default action.

Rules:

- CI mode must never prompt.
- Approval scopes must be explicit: once, session, or policy suggestion.
- Session approvals expire at session end.
- Policy suggestions must not auto-write unless the user explicitly chooses that behavior.
- Every approval/denial must be audited.

---

## 6. Policy Contract

All enforcement surfaces must call the same policy evaluation layer.

Do not implement separate ad hoc allow/deny logic in CLI, MCP, command guard, network guard, or filesystem staging.

Allowed pattern:

```text
action -> normalize -> policy.evaluate(action, context) -> decision -> enforce -> audit
```

Disallowed pattern:

```text
if command contains "rm" then block inside CLI without policy/audit path
```

Heuristics are allowed, but they must feed into policy evaluation or produce auditable decision reasons.

---

## 7. Event Schema Contract

Every event must be schema-versioned and compatible with `schemas/event-v1.json` by v1.0.

Events must be deterministic enough for hash-chain verification. If canonical JSON is not fully implemented initially, the event writer must use stable field ordering and tests must prove stable hashes.

Events must not contain:

- raw secret values;
- unbounded child output;
- unbounded MCP arguments;
- unbounded policy text;
- raw environment dumps.

---

## 8. MCP Contract

MCP stdio proxying is a core v1.0 feature.

For stdio transport:

- Aegis launches the server subprocess.
- Aegis reads client JSON-RPC messages from stdin.
- Aegis writes server JSON-RPC responses to stdout.
- Server stderr is treated as logs, not protocol.
- Protocol messages are bounded.
- Tool/resource/prompt/sampling messages are untrusted.
- Tool arguments are redacted before logs.
- Invalid or oversized messages fail closed for the affected action.

The v1.0 product must support policy mediation for:

- `tools/list`
- `tools/call`
- `resources/list`
- `resources/read`
- `prompts/list`
- `prompts/get`
- `sampling/createMessage` or equivalent sampling requests when encountered

Remote/HTTP MCP can be partial if clearly documented, but stdio must be production-ready.

---

## 9. Red-team Contract

Red-team fixtures must test actual implemented controls, not only mocked decisions.

Acceptable fixture types:

- pure unit fixtures for parser/decision logic;
- integration fixtures using fake agents;
- integration fixtures using fake MCP servers;
- platform-gated fixtures for backend enforcement.

Unacceptable:

- fixtures that pass because expected output was hardcoded;
- fixtures requiring real LLM calls;
- fixtures requiring real external webhook/network services;
- fixtures using real credentials.

Each fixture must state whether it tests:

- decision only;
- wrapper/proxy enforcement;
- OS-level enforcement;
- audit/redaction;
- replay/tamper behavior.

---

## 10. Dependency and Parser Contract

For any parser of untrusted data, define and test limits:

- max file size;
- max message size;
- max nesting depth;
- max collection length;
- max string length;
- timeout or bounded read behavior where applicable.

This applies to:

- policy files;
- YAML/JSON parsing;
- MCP JSON-RPC;
- MCP schemas;
- red-team fixture files;
- command strings;
- URLs/domains;
- audit replay input.

---

## 11. Documentation Contract

Docs and README must use this wording pattern:

Good:

> Aegis reduces blast radius and gives policy/audit controls for AI-agent workflows. Some protections are wrapper/proxy-mediated on macOS and Windows; `aegis doctor` shows active capabilities.

Bad:

> Aegis makes AI agents safe.

Bad:

> Aegis fully sandboxes agents on every OS.

---

## 12. Final Rule for Codex Agents

When uncertain, Codex must implement the narrower, safer behavior and document the limitation rather than inventing broader security guarantees.
