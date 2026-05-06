# Phase 04 CLI Skeleton Plan

## Assumptions

- Phase 04 is CLI-only: no real process supervision, policy matching, MCP proxying, staging engine, or red-team execution.
- Existing Phase 03 core capability model is the source for `doctor`; CLI output must report planned/stub capability status honestly.
- `init` may write a minimal valid-looking YAML policy template directly because full policy parsing belongs to Phase 07.
- Tests should exercise command routing through pure functions and use a temporary directory for `init`.

## Checklist

- [x] Add Phase 04 tests first for top-level help, command help, version aliases, unknown commands, `init`, overwrite refusal, and `doctor`.
- [x] Implement conventional Phase 04 exit code constants.
- [x] Implement command dispatch and command-specific help for all planned commands.
- [x] Implement honest placeholder command handlers for future phases.
- [x] Implement `init` policy creation with `--mode`, `--ci`, `--force`, and overwrite protection.
- [x] Implement `doctor` capability output from `core/platform.zig`.
- [x] Run `zig build`, `zig build test`, and required manual CLI smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Review fix: placeholder commands now return unsupported exit code `4` instead of success when invoked before implementation.
- Review fix: `aegis version --help` now shows command help and `aegis version <extra>` returns usage exit code `2`.
- Manual smoke tests passed:
  - `aegis --help`
  - `aegis help run`
  - `aegis version`
  - `aegis init --mode strict`
  - `aegis doctor`
  - unknown command returned exit code `2`
  - `aegis run -- true` returned unsupported exit code `4`
  - `aegis version --help` returned exit code `0`
  - `aegis version typo` returned usage exit code `2`
- Phase 04 remains CLI-only; no process supervision, policy matching, MCP proxying, staging engine, or red-team execution was implemented.
- `doctor` reports planned capability rows with the existing Phase 03 capability states and does not claim active enforcement.
- `init` writes a minimal `.aegis/policy.yaml`, refuses overwrite without `--force`, and does not persist secrets.

# Phase 05 Session Supervisor Plan

## Assumptions

- Phase 05 owns only direct-child process supervision behind `aegis run`; policy enforcement, audit persistence, env filtering, filesystem staging, command guard, MCP proxying, and sandboxing remain out of scope.
- The CLI should parse `--workspace`, `--mode`, `--session-name`, and `--` while the core supervisor resolves workspace, creates session metadata, launches the child, waits, and reports the result.
- Child stdout/stderr should inherit the terminal for real CLI runs; unit tests should use platform-portable Zig helper invocations or intentionally missing commands.
- Workspace detection should prefer explicit workspace, then nearest parent `.git`, then current working directory, and should not fail outside a Git repository.

## Checklist

- [x] Add Phase 05 tests first for run config parsing, workspace detection, successful child execution, non-zero child exit propagation, missing command errors, and session metadata.
- [x] Implement `src/core/supervisor.zig` with `RunConfig`, `SessionResult`, workspace resolution, session creation, child launch/wait, and exit status mapping.
- [x] Replace `src/cli/run.zig` placeholder with real argument parsing, summary output, useful missing-command errors, and child exit propagation.
- [x] Update run help text to describe Phase 05 options without claiming future enforcement.
- [x] Run `zig build`, `zig build test`, and requested manual smoke tests.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Manual smoke tests passed:
  - `zig-out/bin/aegis run -- echo hello` returned exit code `0` and streamed `hello`.
  - `zig-out/bin/aegis run --workspace . -- echo hello` returned exit code `0` and resolved the workspace to this checkout.
  - `zig-out/bin/aegis run --mode observe -- echo hello` returned exit code `0` and printed `Mode: observe`.
  - `zig-out/bin/aegis run -- /bin/sh -c 'exit 7'` returned exit code `7`.
  - `zig-out/bin/aegis run -- aegis-definitely-missing-command` returned exit code `1` with `command not found`.
- Phase 05 is direct-child supervision only. It does not implement policy enforcement, environment filtering, audit persistence, filesystem staging, command guard, MCP proxying, sandboxing, network guard, approvals, or process-tree containment.
- Session lifecycle events are created in memory only for Phase 06 audit integration points; no persistent event log is written.
- Unit tests suppress child stdout/stderr to avoid corrupting Zig's `--listen` build-test protocol; the real CLI inherits child stdio.
- Windows manual smoke was not run from this macOS checkout; the supervisor tests use Zig child commands for portable coverage, and the Unix-specific `/bin/sh -c 'exit 7'` smoke documents the local exit-code propagation check.

## Review Fixes

- [x] Fixed post-spawn start-hook failures so the supervisor kills/reaps the child before returning the hook error.
- [x] Fixed lifecycle event target ownership so returned events do not point at stack-backed `session.id.slice()` storage.
- [x] Added regression tests for hook-failure cleanup and owned session event target values.
