# Aegis

Aegis is a Zig-based, local-first runtime firewall for AI agents.

Primary promise:

> Run your AI coding agent without giving it your whole laptop.

## Status

Aegis is pre-release scaffold code. Phase 02 only bootstraps the repository, build, module layout, and minimal CLI. It does not yet enforce sandboxing, policy controls, filesystem staging, command mediation, MCP proxying, network controls, audit logging, or secret redaction.

Any command beyond `help` and `version` is intentionally reported as not implemented until later phases add tested behavior.

## Toolchain

This repository is pinned to Zig `0.15.2`.

```bash
zig version
zig build
zig build test
```

## Development

Run the CLI through the build system:

```bash
zig build run -- --help
zig build run -- version
```

The canonical source layout is under `src/`:

- `cli/` parses arguments and renders user-facing output.
- `core/` will hold shared types, errors, sessions, events, decisions, platform helpers, and limits.
- `policy/` will load, validate, compile, evaluate, and explain policy.
- `audit/` will own persistent event writing, replay, hash chains, summaries, and redaction bridges.
- `intercept/` will hold environment, filesystem, command, network, and approval helpers.
- `mcp/` will hold JSON-RPC, stdio transport, proxying, and MCP object mediation.
- `sandbox/` will hold backend selection and honest platform capability reporting.
- `redteam/` will hold deterministic security fixtures and reports.

## Security Claims

No runtime security protection is active in this phase. The current CLI is useful only for bootstrap verification. Future phases must not claim active enforcement until the protection exists, is tested, and is documented.
