# Production Readiness Gates for Aegis v1.0

This file defines the gates that must be satisfied before Aegis can be considered production-ready v1.0.

## Meaning of Production-ready

For Aegis, production-ready means:

- the tool is safe to recommend to developers with clearly documented limits;
- claimed protections are implemented and tested;
- logs do not leak secrets;
- failure modes are understandable;
- release artifacts are reproducible enough for open-source trust;
- cross-platform behavior is known and documented;
- red-team fixtures prove the main security value.

It does not mean perfect containment of malicious code on every operating system.

---


## v1.0 Minimum Enforcement Baseline

Before v1.0, Aegis must provide these implemented and tested controls across all supported platforms:

- environment filtering for child processes;
- redaction before persistent logging;
- policy evaluation and explanations for every security-relevant action;
- tamper-evident session audit logs;
- staged-write review flow for Aegis-mediated writes;
- command risk classification with approval/deny behavior through wrappers/shims and direct Aegis-mediated execution;
- production-ready stdio MCP proxy enforcement;
- network decision engine plus at least proxy/wrapper-mediated enforcement hooks;
- honest capability reporting for transparent enforcement gaps;
- deterministic red-team fixtures that exercise actual implemented controls.

Linux should provide stronger OS-level containment when kernel features are available. macOS and Windows may be partial/wrapper backends for v1.0, but their capability reports and docs must say so clearly.

---

## Per-phase Gate

Every phase must end with:

- `zig build` passing;
- `zig build test` passing;
- relevant command smoke tests passing;
- new tests for new behavior;
- no fake “active” security claims;
- phase handoff completed;
- known limitations documented.

---

## Core Gates

### CLI Gate

- all commands have help;
- unknown commands fail clearly;
- exit codes are stable;
- commands do not silently ignore invalid arguments.

### Session Gate

- `aegis run` launches commands;
- exit codes propagate;
- sessions are uniquely identified;
- workspace detection works;
- session lifecycle events are emitted.

### Audit Gate

- event JSONL is valid;
- event serialization is deterministic;
- hash chain verifies;
- tampering is detected;
- redaction occurs before persistence;
- replay is readable.

### Policy Gate

- policy schema is versioned;
- invalid policy fails with clear error;
- deny priority is tested;
- explanations identify matched rules;
- built-in presets validate;
- `ci` mode never prompts.

### Secret Gate

- common secret env vars are stripped;
- secret-like values are redacted;
- redaction fingerprints are stable;
- synthetic secrets never appear in persistent logs;
- tests prove the above.

### Filesystem Gate

- path normalization is tested;
- workspace containment is tested;
- symlink escape behavior is tested;
- staged writes can be diffed/applied/discarded;
- limitations of interception are documented.

### Command Gate

- high-risk commands are classified;
- command policy can allow/ask/deny;
- CI ask => deny;
- shims avoid recursion;
- decisions are logged.

### MCP Gate

- stdio JSON-RPC proxy works;
- newline-delimited stdio framing is respected;
- invalid/oversized messages fail safely;
- tools/list is logged;
- tools/call is policy-mediated;
- resources/prompts/sampling are handled by v1.0;
- MCP args are redacted before logs.

### Network Gate

- destination matching is tested;
- unknown/direct/private destinations have policy decisions;
- exfil heuristics are tested;
- enforcement level is reported honestly;
- proxy/observe/direct modes are distinguishable.

### Red-team Gate

- at least ten fixtures pass;
- fixtures require no real LLMs;
- fixtures require no real secrets;
- `aegis redteam --ci` fails on regression;
- report is human and machine-readable.

### Platform Gate

- Linux, macOS, and Windows builds exist;
- capability reports are accurate;
- unsupported features are explicit;
- platform docs match `aegis doctor`.

### Release Gate

- version is set;
- release artifacts build;
- checksums generated;
- SBOM hook exists;
- install docs match artifacts;
- release notes and changelog exist.

---

## Final v1.0 Evidence Pack

Before tagging v1.0, produce or update:

```text
README.md
docs/threat-model.md
docs/policy.md
docs/mcp.md
docs/redteam.md
docs/platform-linux.md
docs/platform-macos.md
docs/platform-windows.md
docs/release.md
schemas/policy-v1.json
schemas/event-v1.json
schemas/mcp-manifest-v1.json
SECURITY.md
CHANGELOG.md
```

Attach or publish:

- red-team output;
- checksums;
- release artifacts;
- known limitations;
- smoke-test output.

---

## Blockers to v1.0

Any of the following block v1.0:

- raw synthetic secret appears in persistent logs;
- audit tamper detection does not work;
- policy deny priority is broken;
- CI mode waits for input;
- docs claim unsupported enforcement;
- MCP parser accepts unbounded messages;
- red-team suite cannot run locally;
- release artifacts cannot be built;
- platform capability matrix is missing or inaccurate;
- stdio MCP proxy is not production-ready;
- v1.0 minimum enforcement baseline is not met.
