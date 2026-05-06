# Phase 20 — Security Hardening and Fuzzing

## Objective

Harden Aegis’s security-sensitive surfaces before v1.0.

At the end of this phase, path parsing, policy parsing, command parsing, MCP parsing, secret redaction, audit integrity, and red-team fixtures should have stronger regression coverage and fuzz-style tests where feasible.

---

## Scope

Implement:

- Threat-model-driven tests.
- Fuzz or property tests for parsers.
- Path bypass regression tests.
- Secret redaction regression tests.
- MCP message size limits.
- JSON/YAML parser hardening.
- Audit hash-chain tamper tests.
- Command parser bypass tests.
- Network exfil heuristic tests.
- Security docs updates.
- Disclosure process finalization.

---

## Non-goals

Do not attempt formal verification.

Do not add heavyweight dependencies without strong justification.

Do not claim perfect sandboxing.

---

## Security Surfaces to Harden

### Path Handling

Test:

- `..` traversal.
- Symlinks.
- Hardlinks where feasible.
- Case folding.
- Unicode normalization where feasible.
- Absolute path escapes.
- Windows drive letters.
- UNC paths.
- macOS-style sensitive paths.
- Temporary file rename patterns.

### Command Parsing

Test:

- command chaining
- pipes
- redirects
- subshells
- command substitution
- encoded commands
- PowerShell encoded command
- `curl | sh`
- `wget -O- | bash`
- alias-like strings
- whitespace/quote tricks

### MCP Parsing

Test:

- invalid JSON
- oversized message
- deeply nested schema
- malicious tool descriptions
- malformed JSON-RPC IDs
- unexpected methods
- secret-like arguments
- high-volume tool list

### Secret Redaction

Test:

- synthetic tokens
- fake private keys
- fake JWTs
- fake AWS keys
- high-entropy strings
- repeated secrets
- secrets in URLs
- secrets in MCP args
- secrets in command output if captured

### Audit Integrity

Test:

- modified event
- deleted event
- reordered events
- changed final hash
- invalid previous hash
- summary mismatch

---

## Fuzzing Strategy

If Zig-native fuzzing support is available in the chosen toolchain, add fuzz targets. Otherwise, add deterministic mutation tests.

Targets:

```text
fuzz_policy_parser
fuzz_path_normalizer
fuzz_command_classifier
fuzz_mcp_jsonrpc_parser
fuzz_secret_redactor
```

Place under:

```text
tests/fuzz/
```

or a similar directory.

Fuzz tests should be optional in normal CI if expensive:

```bash
zig build fuzz
```

---

## Security Documentation

Update:

```text
SECURITY.md
docs/threat-model.md
docs/platform-linux.md
docs/platform-macos.md
docs/platform-windows.md
docs/redteam.md
```

Include:

- what Aegis protects
- what it does not protect
- platform limitations
- vulnerability reporting
- safe harbor language if desired
- supported versions
- expected disclosure timeline

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Security regression tests pass.
- Fuzz/mutation targets exist.
- Red-team fixtures pass.
- Audit tamper tests pass.
- MCP oversized/deep inputs are rejected safely.
- Secret redaction tests prove synthetic secrets do not enter logs.
- Threat model docs are updated.
- `SECURITY.md` is production-ready.

---

## Codex Execution Prompt

```text
Implement Phase 20: Security Hardening and Fuzzing.

Add threat-model-driven regression tests, fuzz/mutation targets for parsers, path bypass tests, command bypass tests, MCP malformed/oversized input tests, secret redaction tests, audit tamper tests, and update security docs. Do not claim perfect security.

Run:
- zig build
- zig build test
- aegis redteam --ci
- optional fuzz/mutation tests if available

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Documentation and demo should use the security limits documented here. Do not let marketing copy exceed actual capabilities.


---

## Review Addendum — Hardening Must Close Known Bypass Classes

This phase must convert the threat model into regression tests. At minimum, include tests for path traversal, symlink escape, command obfuscation, MCP oversized/malformed inputs, secret redaction in URLs/args/logs, and audit tampering.

Any discovered bypass that cannot be fixed before v1.0 must be documented as a known limitation and reflected in `aegis doctor` or platform docs if relevant.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
