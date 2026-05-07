# Aegis

Aegis is a Zig-based, local-first runtime firewall for AI agents.

Primary promise:

> Run your AI coding agent without giving it your whole laptop.

## Status

Aegis is pre-release software moving through phased implementation. Current local builds include policy validation/evaluation, audit/replay, staged-write review, command/network decision logic, stdio MCP proxy controls, red-team fixtures, platform capability reporting, policy presets, shell completions, and CI examples.

Aegis does not claim universal transparent sandboxing on every operating system. Use `aegis doctor` to see the actual backend capability status for your machine.

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

Initialize a local policy:

```bash
zig build
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis policy check .aegis/policy.yaml
./zig-out/bin/aegis doctor
```

Useful docs:

- `docs/quickstart.md`
- `docs/presets.md`
- `docs/agent-recipes.md`
- `docs/ci/github-actions.md`

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

Aegis reduces blast radius and improves auditability for agent runs through policy decisions, redaction, staged writes, wrappers/proxies, and platform-specific backend support. Unsupported transparent controls are reported as limited, observe-only, wrapper-only, or unavailable rather than active.
