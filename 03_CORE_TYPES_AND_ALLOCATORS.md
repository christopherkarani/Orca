# Phase 03 — Core Types, Errors, Allocators, and Utilities

## Objective

Create the core data model and shared utilities used by the rest of Aegis.

At the end of this phase, the project should have stable foundational types for sessions, events, decisions, policies, actors, targets, platforms, paths, and errors.

---

## Scope

Implement:

- Core error set.
- Platform detection.
- Session ID generation.
- Event ID generation.
- Timestamp utilities.
- Core event model.
- Decision model.
- Actor/target model.
- Basic path wrapper types.
- Allocation conventions.
- Basic JSON serialization helpers where needed.
- Tests for deterministic core behavior.

---

## Non-goals

Do not implement full policy parsing, audit persistence, process supervision, or security enforcement yet.

---

## Core Types

### Error Set

Create `src/core/errors.zig`:

```zig
pub const AegisError = error{
    PolicyParseFailed,
    PolicyValidationFailed,
    PolicyNotFound,
    AuditLogUnavailable,
    SandboxUnavailable,
    PermissionDenied,
    UserDenied,
    UnsupportedPlatformFeature,
    InputTooLarge,
    InvalidUtf8,
    InvalidPath,
    InvalidCommand,
    InvalidMCPMessage,
    MCPMessageTooLarge,
    SecretRedactionFailed,
    SessionCreateFailed,
};
```

The exact set can evolve, but security-relevant errors should remain explicit.

### Platform

Create `src/core/platform.zig`:

```zig
pub const Os = enum {
    linux,
    macos,
    windows,
    freebsd,
    unknown,
};

pub const Capability = enum {
    process_supervision,
    env_filtering,
    path_staging,
    shell_wrapping,
    path_shims,
    mcp_stdio_proxy,
    network_observe,
    network_enforce,
    strong_sandbox,
};
```

Add a function:

```zig
pub fn detectOs() Os
```

Add capability-reporting stubs that later backends will fill.

### Session

Create `src/core/session.zig`:

```zig
pub const SessionId = struct {
    value: [64]u8,
    len: usize,
};

pub const Session = struct {
    id: SessionId,
    started_at: Timestamp,
    ended_at: ?Timestamp,
    command: []const u8,
    args: []const []const u8,
    workspace_root: []const u8,
    policy_hash: ?[]const u8,
    mode: Mode,
    platform: Os,
};
```

Session IDs should be readable and sortable, for example:

```text
2026-05-05T12-15-30Z_8f1c
```

### Event

Create `src/core/event.zig`:

```zig
pub const EventType = enum {
    session_start,
    session_exit,
    policy_loaded,
    process_launch,
    file_read_attempt,
    file_read_allowed,
    file_read_denied,
    file_write_attempt,
    file_write_staged,
    command_attempt,
    command_allowed,
    command_denied,
    network_connect_attempt,
    network_connect_allowed,
    network_connect_denied,
    mcp_initialize,
    mcp_tools_list,
    mcp_tool_call,
    secret_redacted,
    user_approval,
    user_denial,
};
```

### Decision

```zig
pub const DecisionResult = enum {
    allow,
    deny,
    ask,
    redact,
    stage,
    broker,
    observe,
};

pub const Decision = struct {
    result: DecisionResult,
    rule_id: ?[]const u8,
    reason: []const u8,
    risk_score: ?u8,
    requires_user: bool,
};
```

---

## Allocation Rules

Create a short document or module comment explaining allocator conventions:

- CLI command lifetime: use an arena allocator.
- Session lifetime: use a session arena.
- Persistent audit data: serialize before freeing.
- Untrusted input parsing: enforce max sizes.
- No global allocator dependency hidden in core types.

---

## Utility Modules

Add utilities for:

- Timestamp formatting.
- Hex encoding small byte arrays.
- Stable short random suffix generation.
- Safe string duplication.
- Case-insensitive comparison where needed.
- Bounded string buffers for IDs.

---

## Tests

Add tests for:

- Platform detection returns a valid enum.
- Session ID generation produces non-empty unique-ish IDs.
- Event type string conversion works.
- Decision result string conversion works.
- Timestamp formatting is stable enough for filenames.
- Error set imports compile across modules.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Core modules compile without circular dependencies.
- Session IDs can be generated.
- Event and decision types can be created in tests.
- Platform detection works on the current OS.
- Module comments explain allocation conventions.

---

## Codex Execution Prompt

```text
Implement Phase 03: Core Types, Errors, Allocators, and Utilities.

Add the core Aegis domain model in Zig: errors, platform detection, sessions, events, decisions, actors, targets, timestamps, and utility helpers. Keep everything dependency-light and testable. Do not implement full policy parsing, audit logging, process supervision, or enforcement yet.

Run:
- zig build
- zig build test

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The CLI skeleton will import these types. Keep APIs small and stable. Avoid premature abstraction.


---

## Review Addendum — Core Types Must Support All Enforcement Surfaces

The core model must be broad enough for later phases. Add an `Action` or equivalent union early so policy evaluation can cover:

- environment variable exposure;
- file read/write;
- command execution;
- network connection;
- MCP tool/resource/prompt/sampling;
- approval decisions;
- staging decisions.

Do not let each enforcement surface invent unrelated decision structures.


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
