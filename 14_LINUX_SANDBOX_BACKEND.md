# Phase 14 — Linux Sandbox Backend

## Objective

Implement the strongest Linux backend for Aegis v1.0.

At the end of this phase, Linux should provide stronger containment than wrapper-only mode, and `aegis doctor` should accurately report Linux capabilities.

---

## Scope

Implement Linux-specific backend features where available:

- Process tree supervision.
- Environment lockdown.
- Working directory isolation.
- Optional user namespace support.
- Optional mount namespace support.
- Optional seccomp-bpf support.
- Optional Landlock support where available.
- Optional cgroup integration.
- Backend capability detection.
- Linux-specific tests.
- Clear fallback behavior.

---

## Non-goals

Do not require root for normal local development.

Do not break systems where namespaces or Landlock are unavailable.

Do not claim a feature is active unless it is actually active.

---

## Backend Design

Create or extend:

```text
src/sandbox/backend.zig
src/sandbox/linux.zig
```

Suggested interface:

```zig
pub const SandboxCapabilities = struct {
    process_supervision: bool,
    env_filtering: bool,
    path_staging: bool,
    shell_wrapping: bool,
    path_shims: bool,
    network_observe: bool,
    network_enforce: bool,
    user_namespaces: bool,
    mount_namespaces: bool,
    seccomp: bool,
    landlock: bool,
    strong_sandbox: bool,
};

pub const Backend = struct {
    capabilities: SandboxCapabilities,
    prepare: fn (...) anyerror!PreparedSandbox,
    launch: fn (...) anyerror!RunResult,
};
```

---

## Capability Levels

Report user-facing levels:

| Level | Meaning |
|---|---|
| `observe` | Logs only |
| `wrapper` | Env/PATH/shell controls |
| `partial` | Some OS restrictions active |
| `strong` | Meaningful OS sandbox active |
| `unavailable` | Feature not available |

Example `aegis doctor`:

```text
Linux backend:
  env filtering: active
  path staging: active
  shell shims: active
  user namespace: active
  mount namespace: active
  seccomp: active
  landlock: unavailable
  network enforcement: partial
  strong sandbox: active
```

---

## Filesystem Isolation

Where feasible:

- Restrict visible paths to workspace and allowed system paths.
- Deny protected secret paths.
- Mount staging overlay if feasible.
- Prevent symlink escapes.
- Deny writes outside workspace/staging.

If full mount isolation is not feasible for this phase, implement capability-detected fallback and document.

---

## Process Restrictions

Where feasible:

- Drop privileges where possible.
- Prevent privilege escalation.
- Restrict subprocess capabilities.
- Supervise process tree.
- Kill descendants on session exit.

---

## Network

If direct network enforcement is feasible:

- Apply network mode `off` where possible.
- Deny private ranges where possible.
- Otherwise expose `partial` and rely on proxy/wrapper controls.

---

## Tests

Add Linux-gated tests:

- Capability detection.
- Sandbox launches command.
- Child cannot see denied env var.
- Child cannot read fixture secret path if backend supports restriction.
- Child cannot write outside workspace if backend supports restriction.
- Process tree cleanup.
- Fallback path works when strong features unavailable.

Do not make CI fail on systems lacking optional kernel features. Tests should skip with clear messages.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Linux backend compiles on Linux.
- Non-Linux builds are not broken.
- `aegis doctor` reports Linux capabilities accurately.
- Strong backend activates when supported.
- Fallback backend works when features are unavailable.
- Red-team fixtures pass or clearly identify unsupported features.
- Docs describe Linux backend limitations.

---

## Codex Execution Prompt

```text
Implement Phase 14: Linux Sandbox Backend.

Add Linux-specific sandbox capability detection and stronger runtime controls where feasible, including process supervision and optional namespace/seccomp/Landlock support. Keep fallbacks safe and honest. Add Linux-gated tests and update doctor output.

Run:
- zig build
- zig build test
- Linux-specific smoke tests if running on Linux
- aegis doctor

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

macOS backend should follow the same backend interface and capability vocabulary.


---

## Review Addendum — Linux Backend Must Be Capability-driven

The Linux backend should activate stronger features only after runtime detection. Tests must be able to skip unsupported kernel features while still testing fallback behavior.

`strong_sandbox` should be true only when meaningful OS-level restrictions are active, not merely because wrappers are active.


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
