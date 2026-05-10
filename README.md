# Orca

The open-source firewall for AI agents. Run coding agents, local automations, and agent-host tools without giving them your whole laptop.

## Why Orca Exists

AI coding agents, local automations, and agent-host tools can read files, run commands, use external tools, and touch sensitive state. Orca provides local policy, redaction, audit, replay, and plugin guardrails so you can supervise agent sessions with explicit rules and tamper-evident logs.

## What Orca Does

- **`orca run`** — launch an agent or command as an Orca-managed child process with filtered environment variables and policy checks.
- **Policy checks** — validate commands, file operations, and network requests against local policy before allowing them.
- **Secret redaction** — detect and redact sensitive values from environment variables and logs.
- **Audit logs** — write tamper-evident session events with hash-chain verification.
- **Replay** — replay a session from audit logs to inspect exactly what happened.
- **Red-team fixtures** — run deterministic, local-only synthetic tests against Orca policy.
- **Plugin doctor** — diagnose Orca installation, plugin status, and platform capabilities.
- **Codex plugin** — host-native skills and hooks that call Orca CLI for policy decisions.
- **Claude Code plugin** — host-native skills and hooks that call Orca CLI for policy decisions.
- **OpenCode plugin** — host-native hooks that call Orca CLI for policy decisions.

Orca is not a SaaS product, hosted dashboard, monetization layer, or telemetry service. It is a local CLI and library built around explicit policy, wrapper/proxy mediation, redaction, and honest platform capability reporting.

## Quick Start

Build from source with Zig `0.15.2`:

```sh
zig build
./zig-out/bin/orca doctor
./zig-out/bin/orca init --preset generic-agent
./zig-out/bin/orca run -- echo hello
./zig-out/bin/orca replay --session last --verify
./zig-out/bin/orca redteam --ci
```

See [Quickstart](docs/quickstart.md) for the full first-run path.

## Agent Host Plugins

Orca includes local plugin integrations for Codex, Claude Code, OpenCode, and OpenClaw. The plugins add host-native skills and lifecycle hooks that call the Orca CLI for policy decisions, red-team checks, replay, and plugin diagnostics.

- [Codex plugin](docs/integrations/codex.md)
- [Claude Code plugin](docs/integrations/claude-code.md)
- [OpenCode plugin](docs/integrations/opencode.md)
- [OpenClaw plugin](docs/integrations/openclaw.md)
- [Orca CLI plugin surface](docs/integrations/orca-cli-plugin.md)
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)

Plugins are integration layers. Host hooks are limited by host capabilities. Orca only protects sessions and actions routed through Orca or host hooks. The strongest local protection remains running the agent through `orca run`; plugins provide native commands, hooks, and guardrails inside supported agent hosts.

## Installing Plugin Artifacts

Plugin packages are produced under `dist/plugins/` after running the packaging script:

```sh
./scripts/package-plugins.sh
```

Artifacts include:

```text
 dist/plugins/orca-codex-plugin-vX.Y.Z.zip
 dist/plugins/orca-claude-code-plugin-vX.Y.Z.zip
 dist/plugins/orca-opencode-plugin-vX.Y.Z.zip
 dist/plugins/orca-openclaw-plugin-vX.Y.Z.zip
 dist/plugins/orca-plugin-checksums.txt
```

Always verify checksums before installing:

```sh
sha256sum -c dist/plugins/orca-plugin-checksums.txt
```

Then point Codex, Claude Code, OpenCode, or OpenClaw at the extracted plugin directory. See the per-host install guides above for details.

### Repo marketplace install

You can also install Orca plugins by adding this repository as a plugin marketplace source:

**Codex:**
```bash
codex plugin marketplace add chriskarani/orca
```
Then install Orca from Codex's plugin UI/directory after adding the marketplace.

**Claude Code:**
```bash
claude plugin marketplace add chriskarani/orca
claude plugin install orca@orca --scope user
```

Or inside Claude Code:
```text
/plugin marketplace add chriskarani/orca
/plugin install orca@orca
/reload-plugins
```

These commands add the Orca repository as a plugin marketplace source. This is not the same as being listed in the official Codex or Claude marketplace. Official marketplace availability is a separate process; repo marketplace support is available now.

## Security Model

- **Orca reduces blast radius.** It filters environments, checks commands, and writes audit logs for child sessions it launches.
- **Orca is not a perfect sandbox.** It works within OS constraints and honest capability reporting.
- **Plugins are integration layers.** They call the Orca CLI instead of duplicating policy logic.
- **Host hooks are limited by host capabilities.** Orca cannot enforce what the host IDE does not expose.
- **Orca only protects sessions and actions routed through Orca or host hooks.** Agents launched outside Orca are not protected.
- **The strongest protection remains `orca run -- <agent-command>`.**

## What Orca Does Not Promise

- No perfect sandboxing claim.
- No universal transparent file enforcement claim.
- No universal transparent network enforcement claim.
- No protection for agents launched outside Orca.
- No protection against root, admin, kernel, or debugger compromise.
- No protection against users approving unsafe actions.
- No safety for arbitrary malicious code or untrusted binaries.
- The current plugin release does not add MCP server behavior or drone-specific plugin features.

## Platform Support

Capability states use the current `orca doctor` vocabulary: `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, `unavailable`, and `unsupported`.

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

Run `./zig-out/bin/orca doctor` on your machine for the authoritative local report. See [Linux](docs/platform-linux.md), [macOS](docs/platform-macos.md), and [Windows](docs/platform-windows.md).

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

- [Orca CLI plugin surface](docs/integrations/orca-cli-plugin.md)
- [Codex plugin](docs/integrations/codex.md)
- [Claude Code plugin](docs/integrations/claude-code.md)
- [OpenCode plugin](docs/integrations/opencode.md)
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)

## Development

```sh
zig build
zig build test
./zig-out/bin/orca doctor
./zig-out/bin/orca redteam --ci
./scripts/package-plugins.sh
```

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), add deterministic tests or fixtures for security-sensitive changes, and run:

```sh
zig build
zig build test
./zig-out/bin/orca redteam --ci
```

For fixture work, read [Contributing fixtures](docs/contributing-fixtures.md).

## Security

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not include real credentials or proprietary logs in reports.
