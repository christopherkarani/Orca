# Phase 02 Repository Bootstrap Plan

## Assumptions

- Phase 02 is scaffold-only: no sandboxing, policy enforcement, MCP proxying, staged writes, network control, telemetry, SaaS, or monetization.
- The local development Zig toolchain is `0.15.2`; this phase pins that version visibly and keeps build/test compatible with it.
- CLI behavior in this phase is limited to help, version, and honest non-implemented command placeholders.

## Checklist

- [x] Create Zig build metadata and binary/test targets.
- [x] Implement minimal CLI dispatch for `--help`, `help`, `version`, and unknown commands.
- [x] Add canonical source module tree with compiling placeholders.
- [x] Add focused tests for help, version, and unknown-command behavior.
- [x] Add bootstrap docs, sample policy/fixture directories, dependency notes, and handoff location.
- [x] Run `zig build`, `zig build test`, and phase smoke checks.

## Review

- `zig build` passed.
- `zig build test` passed.
- `zig build run -- --help` printed the Phase 02 help text.
- `zig build run -- version` printed `aegis 0.0.0-dev`.
- `./zig-out/bin/aegis not-a-command` exited with code `64` and a useful unknown-command message.
