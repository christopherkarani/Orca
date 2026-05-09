# Aegis

The open-source firewall for AI agents. Run coding agents, local automations, and agent-host tools without giving them your whole laptop.

## Why Aegis Exists

AI coding agents, local automations, and agent-host tools can read files, run commands, use external tools, and touch sensitive state. Aegis provides local policy, redaction, audit, replay, and plugin guardrails so you can supervise agent sessions with explicit rules and tamper-evident logs.

## What Aegis Does

- **`aegis run`** — launch an agent or command as an Aegis-managed child process with filtered environment variables and policy checks.
- **Policy checks** — validate commands, file operations, and network requests against local policy before allowing them.
- **Secret redaction** — detect and redact sensitive values from environment variables and logs.
- **Audit logs** — write tamper-evident session events with hash-chain verification.
- **Replay** — replay a session from audit logs to inspect exactly what happened.
- **Red-team fixtures** — run deterministic, local-only synthetic tests against Aegis policy.
- **Plugin doctor** — diagnose Aegis installation, plugin status, and platform capabilities.
- **Codex plugin** — host-native skills and hooks that call Aegis CLI for policy decisions.
- **Claude Code plugin** — host-native skills and hooks that call Aegis CLI for policy decisions.

Aegis is not a SaaS product, hosted dashboard, monetization layer, or telemetry service. It is a local CLI and library built around explicit policy, wrapper/proxy mediation, redaction, and honest platform capability reporting.

## Quick Start

Build from source with Zig `0.15.2`:

```sh
zig build
./zig-out/bin/aegis doctor
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis run -- echo hello
./zig-out/bin/aegis replay --session last --verify
./zig-out/bin/aegis redteam --ci
```

See [Quickstart](docs/quickstart.md) for the full first-run path.

## Agent Host Plugins

Aegis includes local plugin integrations for Codex and Claude Code. The plugins add host-native skills and lifecycle hooks that call the Aegis CLI for policy decisions, red-team checks, replay, and plugin diagnostics.

- [Codex plugin](docs/integrations/codex.md)
- [Claude Code plugin](docs/integrations/claude-code.md)
- [Aegis CLI plugin surface](docs/integrations/aegis-cli-plugin.md)
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)

Plugins are integration layers. Host hooks are limited by host capabilities. Aegis only protects sessions and actions routed through Aegis or host hooks. The strongest local protection remains running the agent through `aegis run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

## Installing Plugin Artifacts

Plugin packages are produced under `dist/plugins/` after running the packaging script:

```sh
./scripts/package-plugins.sh
```

Artifacts include:

```text
dist/plugins/aegis-codex-plugin-vX.Y.Z.zip
dist/plugins/aegis-claude-code-plugin-vX.Y.Z.zip
dist/plugins/aegis-plugin-checksums.txt
```

Always verify checksums before installing:

```sh
sha256sum -c dist/plugins/aegis-plugin-checksums.txt
```

Then point Codex or Claude Code at the extracted plugin directory. See the per-host install guides above for details.

Official marketplace availability is not yet implemented; use local path or release artifact install until distribution is available.

## Security Model

- **Aegis reduces blast radius.** It filters environments, checks commands, and writes audit logs for child sessions it launches.
- **Aegis is not a perfect sandbox.** It works within OS constraints and honest capability reporting.
- **Plugins are integration layers.** They call the Aegis CLI instead of duplicating policy logic.
- **Host hooks are limited by host capabilities.** Aegis cannot enforce what the host IDE does not expose.
- **Aegis only protects sessions and actions routed through Aegis or host hooks.** Agents launched outside Aegis are not protected.
- **The strongest protection remains `aegis run -- <agent-command>`.**

## What Aegis Does Not Promise

- No perfect sandboxing claim.
- No universal transparent file enforcement claim.
- No universal transparent network enforcement claim.
- No protection for agents launched outside Aegis.
- No protection against root, admin, kernel, or debugger compromise.
- No protection against users approving unsafe actions.
- No safety for arbitrary malicious code or untrusted binaries.
- The current plugin release does not add MCP server behavior or drone-specific plugin features.

## Platform Support

Capability states use the current `aegis doctor` vocabulary: `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, `unavailable`, and `unsupported`.

| Feature | Linux | macOS | Windows |
|---|---|---|---|
| Launch arbitrary command | active | active | active |
| Env filtering | active | active | active |
| Secret redaction | active | active | active |
| Audit/replay | active | active | active |
| Staged writes | active | active | active |
| Command guard | wrapper-only | wrapper-only | wrapper-only |
| Shell/PATH shims | wrapper-only | wrapper-only | wrapper-only |
| MCP stdio proxy | active | active | active |
| MCP manifests | active | active | active |
| MCP sampling controls | active | active | active |
| Network decision engine | active | active | active |
| Proxy-mediated network enforcement | unavailable | unavailable | unavailable |
| Transparent network enforcement | observe-only | limited | limited |
| Transparent filesystem enforcement | unavailable; staged writes active | limited | limited |
| Strong sandbox | unavailable | unavailable | unavailable |
| Process cleanup | active or partial | active | partial |
| Red-team suite | active | active | active |

Run `./zig-out/bin/aegis doctor` on your machine for the authoritative local report. See [Linux](docs/platform-linux.md), [macOS](docs/platform-macos.md), and [Windows](docs/platform-windows.md).

## Documentation

- [Quickstart](docs/quickstart.md)
- [Install](docs/install.md)
- [Threat model](docs/threat-model.md)
- [Policy](docs/policy.md)
- [MCP](docs/mcp.md)
- [Red-team](docs/redteam.md)
- [Agent recipes](docs/agent-recipes.md)
- [CI](docs/ci.md)
- [Replay](docs/replay.md)
- [Filesystem staging](docs/filesystem-staging.md)
- [Network](docs/network.md)
- [Commands](docs/commands.md)
- [Compatibility matrix](docs/compatibility.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Release](docs/release.md)

Plugin docs:

- [Aegis CLI plugin surface](docs/integrations/aegis-cli-plugin.md)
- [Codex plugin](docs/integrations/codex.md)
- [Claude Code plugin](docs/integrations/claude-code.md)
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)

## Development

```sh
zig build
zig build test
./zig-out/bin/aegis doctor
./zig-out/bin/aegis redteam --ci
./scripts/package-plugins.sh
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), add deterministic tests or fixtures for security-sensitive changes, and run:

```sh
zig build
zig build test
./zig-out/bin/aegis redteam --ci
```

For fixture work, read [Contributing fixtures](docs/contributing-fixtures.md).

## Security

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not include real credentials or proprietary logs in reports.
