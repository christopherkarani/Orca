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
