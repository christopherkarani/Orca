# Phase 05 — Session Supervisor

## Objective

Implement the process/session supervisor behind `aegis run`.

At the end of this phase, Aegis should launch a child command, filter basic session metadata through the core model, track its lifecycle, mirror its exit code, and produce a simple session summary.

---

## Scope

Implement:

- `aegis run -- <command> [args...]`
- Session creation.
- Workspace detection.
- Child process launch.
- Signal/interrupt handling where feasible.
- Exit code propagation.
- Session summary printing.
- Basic process event creation in memory.
- Initial supervisor abstraction.

---

## Non-goals

Do not implement full policy enforcement, environment filtering, audit persistence, filesystem staging, command guard, or sandboxing yet.

---

## CLI Behavior

Examples:

```bash
aegis run -- echo hello
aegis run --workspace . -- echo hello
aegis run --mode observe -- echo hello
aegis run --session-name test -- echo hello
```

Expected output can be simple:

```text
Aegis session started: 2026-05-05T12-15-30Z_8f1c
Workspace: /path/to/repo
Mode: observe

hello

Aegis session ended: exit code 0
```

The child process stdout/stderr should flow naturally to the terminal.

---

## Supervisor Responsibilities

Create or fill `src/core/supervisor.zig`.

Responsibilities:

1. Accept a `RunConfig`.
2. Resolve workspace root.
3. Create `Session`.
4. Prepare child process.
5. Launch child process.
6. Wait for exit.
7. Capture exit status.
8. Return a `SessionResult`.

Suggested types:

```zig
pub const RunConfig = struct {
    command: []const u8,
    args: []const []const u8,
    workspace: ?[]const u8,
    mode: Mode,
    session_name: ?[]const u8,
};

pub const SessionResult = struct {
    session: Session,
    exit_code: i32,
};
```

---

## Workspace Detection

Detect workspace root as:

1. `--workspace` argument if provided.
2. Nearest parent directory containing `.git`.
3. Current working directory.

Do not fail if not in a Git repository.

---

## Exit Code Behavior

- If the child exits with code `N`, Aegis exits with code `N`.
- If Aegis fails before launching child, return a CLI/system error.
- If child is terminated by signal, report it clearly and return non-zero.
- If the command does not exist, report a useful error.

---

## Process Tree Note

For this phase, supervising only the direct child is acceptable. Later phases will improve process tree behavior and shell/PATH shims.

---

## Tests

Add tests for:

- `RunConfig` construction.
- Workspace detection.
- Running a simple successful command.
- Running a command that exits non-zero.
- Missing command behavior.
- Session metadata is populated.

Use small platform-portable commands where possible. If `echo` or shell behavior differs across OSes, use the Aegis test binary or Zig-generated helper process instead.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis run -- echo hello` launches and exits 0 on Unix-like systems.
- Equivalent Windows-compatible smoke test exists or is documented.
- Child process exit code is propagated.
- Workspace detection works.
- Session start/end messages print.
- No security enforcement is claimed yet.

---

## Codex Execution Prompt

```text
Implement Phase 05: Session Supervisor.

Replace the placeholder `aegis run` with a real process launcher. Create session metadata, detect workspace root, launch the child command, stream stdout/stderr, wait for exit, and propagate the child exit code. Keep enforcement out of scope.

Run:
- zig build
- zig build test
- manual smoke test: aegis run -- echo hello

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The audit phase will persist session events. Make sure the supervisor exposes lifecycle points where audit events can be emitted.


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
