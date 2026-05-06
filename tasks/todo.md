# Phase 03 Core Types and Allocators Plan

## Assumptions

- Phase 03 is core-only: no policy parsing, audit persistence, process supervision, MCP proxy implementation, sandbox enforcement, staged writes, or network enforcement.
- Core modules must remain dependency-light and avoid hidden global allocator dependencies.
- Security-sensitive data models should be explicit and bounded, but later enforcement phases will own full policy/audit behavior.

## Checklist

- [x] Add Phase 03 tests first for platform detection, IDs, timestamps, string conversions, actions, paths, and error imports.
- [x] Implement explicit core errors, limits, utilities, timestamp formatting, platform/capability reporting, sessions, events, decisions, actors, targets, actions, and path wrappers.
- [x] Keep module exports stable through `src/core/mod.zig` and avoid circular imports.
- [x] Run `zig build` and `zig build test`.
- [x] Document review results, limitations, security notes, and acceptance criteria status.

## Review

- `zig build` passed.
- `zig build test` passed.
- Core modules compile through `src/core/mod.zig` without circular imports.
- Phase 03 remains core-only; no policy parser, audit writer, sandbox, MCP proxy, staged write engine, command guard, or network enforcement was implemented.
- Capability reporting uses explicit states and intentionally reports Phase 03 backend capabilities as `unknown` or `unavailable`.
