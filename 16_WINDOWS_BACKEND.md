# Phase 16 — Windows Backend

## Objective

Implement a useful Windows backend with PowerShell/cmd support and honest capability reporting.

At the end of this phase, Aegis should build and run on Windows, launch child commands, filter environment variables, support staged writes, provide command guarding for common Windows shells, and report capabilities accurately.

---

## Scope

Implement Windows-specific backend features:

- Platform detection.
- Process launch support.
- Environment filtering.
- PATH shim support.
- PowerShell/cmd wrapper support.
- Windows path normalization.
- Protected path patterns.
- Basic Job Object/process cleanup support where feasible.
- Capability reporting.
- Windows-gated tests.

---

## Non-goals

Do not require admin privileges for normal local development.

Do not implement a Windows Filtering Platform driver for v1.0.

Do not claim full transparent network or filesystem enforcement unless implemented.

---

## Windows Path Handling

Handle:

- Drive letters.
- UNC paths.
- Backslash/forward slash normalization.
- Case-insensitive comparisons.
- `%USERPROFILE%`.
- `%APPDATA%`.
- `%LOCALAPPDATA%`.
- Path traversal.
- Symlinks/junctions where feasible.

Default protected paths should include:

```text
%USERPROFILE%\.ssh\**
%USERPROFILE%\.aws\**
%APPDATA%\GitHub CLI\**
%APPDATA%\gh\**
%LOCALAPPDATA%\Google\Chrome\User Data\**
%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\**
```

Use test fixtures rather than real user directories.

---

## Shell and Command Support

Support wrappers/shims for:

- `cmd.exe`
- `powershell.exe`
- `pwsh.exe`
- common commands:
  - `curl`
  - `git`
  - `npm`
  - `python`
  - `node`

Classify high-risk Windows commands:

- `powershell -EncodedCommand`
- `Invoke-WebRequest ... | iex`
- `Remove-Item -Recurse -Force`
- `Start-Process -Verb RunAs`
- credential-file reads
- registry writes if handled

---

## Process Cleanup

Use Windows process controls where feasible to clean up child processes on session exit. Job Objects are a likely mechanism, but implement only if feasible in current scope.

---

## Doctor Output

Example:

```text
Windows backend:
  env filtering: active
  path staging: active
  cmd wrapper: active
  PowerShell wrapper: active
  process cleanup: partial
  transparent file enforcement: limited
  transparent network enforcement: limited
  strong sandbox: unavailable
```

---

## Tests

Add Windows-gated tests for:

- Platform detection.
- Windows path normalization.
- Protected path matching.
- Env filtering.
- PowerShell encoded command classification.
- `cmd` risky command classification.
- Staging with Windows paths.
- Process launch.

Do not make non-Windows builds fail.

---

## Acceptance Criteria

- `zig build` succeeds on Windows.
- `zig build test` succeeds on Windows.
- Non-Windows builds are not broken.
- `aegis doctor` reports Windows capabilities accurately.
- PowerShell/cmd risky command patterns are classified.
- Windows path normalization tests pass.
- Docs explain Windows limitations.

---

## Codex Execution Prompt

```text
Implement Phase 16: Windows Backend.

Add Windows-specific backend support for process launch, env filtering, PATH shims, cmd/PowerShell wrappers, Windows path normalization, protected path patterns, process cleanup where feasible, and doctor capability reporting. Keep enforcement claims honest.

Run:
- zig build
- zig build test
- Windows smoke tests if running on Windows
- aegis doctor

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Advanced MCP features should remain cross-platform and not depend on platform-specific sandboxing.


---

## Review Addendum — Windows Backend Honesty

Windows support must be useful even if transparent enforcement is limited. Prioritize process launch, env filtering, path normalization, PowerShell/cmd classification, staging, and clear capability reporting.

Tests should simulate Windows path patterns and must not require administrator privileges.


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
