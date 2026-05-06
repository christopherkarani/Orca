# Phase 15 — macOS Backend

## Objective

Implement a useful macOS backend with honest capability reporting.

At the end of this phase, Aegis should build and run cleanly on macOS, provide practical local controls, integrate with existing supervisor/env/staging/shim systems, and clearly report which protections are active or limited.

---

## Scope

Implement macOS-specific backend features:

- Platform detection.
- Process launch support.
- Environment filtering support.
- PATH shim support.
- Shell wrapper support.
- Filesystem staging support.
- Process tree cleanup where feasible.
- Capability reporting.
- macOS path normalization specifics.
- macOS-specific tests where feasible.
- Documentation of limitations.

---

## Non-goals

Do not require special entitlements or kernel extensions for v1.0.

Do not claim transparent full filesystem or network enforcement if not actually implemented.

Do not build a GUI or menu bar app.

---

## Backend Design

Extend:

```text
src/sandbox/macos.zig
src/sandbox/backend.zig
```

Use the same capability vocabulary from the Linux phase:

- `observe`
- `wrapper`
- `partial`
- `strong`
- `unavailable`

---

## macOS-Specific Path Concerns

Handle:

- Case-insensitive filesystems.
- `~/Library` protected/sensitive locations.
- Application Support paths.
- Keychain-related files.
- Browser profile paths.
- iCloud Drive paths if present.
- Symlinks and aliases where feasible.

Default protected paths should include:

```text
~/.ssh/**
~/.aws/**
~/.config/gh/**
~/Library/Application Support/**/Cookies*
~/Library/Application Support/**/Login Data*
~/Library/Keychains/**
```

Avoid brittle absolute assumptions where possible.

---

## Process and Shell Support

Support:

- Launching arbitrary child commands.
- Filtering env.
- Prepending shim directory to PATH.
- Wrapping common shells:
  - `sh`
  - `bash`
  - `zsh`
- Cleaning child process on Ctrl-C where feasible.

---

## Network

Use existing network guard interfaces. Report transparent enforcement as limited unless implemented.

Proxy-mediated enforcement is acceptable for v1.0 if documented.

---

## Doctor Output

Example:

```text
macOS backend:
  env filtering: active
  path staging: active
  shell shims: active
  process supervision: active
  transparent file enforcement: limited
  transparent network enforcement: limited
  strong sandbox: unavailable
```

---

## Tests

Add macOS-gated tests for:

- Platform detection.
- Path normalization.
- Protected path matching.
- Session launch.
- Env filtering.
- Shim PATH insertion.
- Staging workflow.
- Process cleanup if feasible.

Tests must not access real secrets. Use temporary directories that simulate macOS paths.

---

## Acceptance Criteria

- `zig build` succeeds on macOS.
- `zig build test` succeeds on macOS.
- Non-macOS builds are not broken.
- `aegis doctor` reports macOS capabilities accurately.
- Core red-team fixtures run on macOS where possible.
- Docs clearly explain macOS limitations.

---

## Codex Execution Prompt

```text
Implement Phase 15: macOS Backend.

Add macOS-specific backend support for process launch, env filtering, PATH shims, shell wrappers, path normalization, protected path patterns, staging integration, process cleanup, and doctor capability reporting. Keep transparent enforcement claims honest.

Run:
- zig build
- zig build test
- macOS smoke tests if running on macOS
- aegis doctor

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Windows backend should mirror the same capability model and avoid disrupting Unix-like behavior.


---

## Review Addendum — macOS Backend Honesty

macOS developer adoption matters, but v1.0 must not overstate macOS containment. If controls are wrapper/staging/proxy-level, doctor and docs must say so.

Use temporary fixture paths to simulate sensitive macOS paths in tests; never inspect real browser/keychain directories.


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
