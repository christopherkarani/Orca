# Aegis

The open-source firewall for AI agents.

Run coding agents, MCP servers, and local automations without giving them your whole laptop.

## What Aegis Is

Aegis is a local, policy-driven runtime firewall for agent sessions. It launches an agent or automation as an Aegis-managed child process, filters its environment, applies command and network policy decisions, stages Aegis-mediated writes for review, proxies stdio MCP traffic, and writes tamper-evident audit logs that can be replayed later.

Aegis is not a SaaS product, hosted dashboard, monetization layer, or telemetry service. It is a local CLI and library built around explicit policy, wrapper/proxy mediation, redaction, and honest platform capability reporting.

## Product Split

Phase 23 introduced the monorepo product contract. Phase 24 hardened Aegis Core as the shared engine facade used by CLI and Edge. Phase 25 keeps the CLI as the stable desktop and CI product while hardening the post-split command surface. Phase 26 adds Edge domain and safety schema contracts without enabling drone command mediation:

- **Aegis Core** (`packages/core/`): shared policy, decision, audit, event, schema, replay, redaction, fixture, red-team, capability, experimental ABI skeleton, and platform-independent utility contracts.
- **Aegis CLI** (`packages/cli/`): the existing desktop and CI AI-agent runtime firewall exposed as the `aegis` binary.
- **Aegis Edge** (`packages/edge/`): a drone and robotics safety-policy and audit runtime scaffold with Phase 26 domain types and safety schema descriptors for future phases.

Aegis Edge remains scaffold-only for runtime behavior. It can call Aegis Core for placeholder action decisions, redaction, and audit construction, and Phase 26 adds validation-only Edge domain/schema types. It is not a flight controller, not an autopilot replacement, not detect-and-avoid, and not regulatory approval or certification. It must not be used for real flight until later simulation, bench, and customer safety validation phases are complete.

## Install

Build from source with Zig `0.15.2`:

```sh
zig build
./zig-out/bin/aegis version --json
```

Install scripts and release packaging templates live in [`scripts/`](docs/install.md) and [`packaging/`](packaging/README.md). Do not run remote installers blindly; download artifacts, verify checksums from `dist/checksums.txt`, then install manually or with the platform script.

```sh
./scripts/build-release.sh
./scripts/generate-checksums.sh
shasum -a 256 -c dist/checksums.txt
```

See [Install](docs/install.md) for macOS, Linux, and Windows notes.

## Quickstart

```sh
zig build
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis policy check .aegis/policy.yaml
./zig-out/bin/aegis doctor
./zig-out/bin/aegis run -- echo hello
./zig-out/bin/aegis replay --session last --verify
```

See [Quickstart](docs/quickstart.md) for the full first-run path.

## Scary Demo

The deterministic local demo shows a malicious README asking an agent to read `.env`, then a fake agent trying command and network-like exfiltration paths with synthetic data only.

```sh
cd examples/leaky-agent-demo
./run-demo.sh
../../zig-out/bin/aegis replay --session last --verify
```

The demo uses no LLM, no API keys, no external network, and no real secret paths. It demonstrates Aegis wrapper-mediated command denial, network policy decisions, redaction, audit logs, and replay. See [the demo README](examples/leaky-agent-demo/README.md).

## Run A Protected Session

```sh
./zig-out/bin/aegis run --policy policies/presets/generic-agent.yaml --mode strict -- zig build test
```

`aegis run` protects the direct child session that Aegis launches. It does not protect agents or subprocesses launched outside Aegis.

## Replay Audit Logs

```sh
./zig-out/bin/aegis replay --session last
./zig-out/bin/aegis replay --session last --verify
./zig-out/bin/aegis replay --session last --json
```

Replay reads `.aegis/sessions/<session>/events.jsonl`, `summary.json`, and `summary.md`, then verifies the hash chain when requested.

## Review Staged Writes

```sh
./zig-out/bin/aegis diff --session last
./zig-out/bin/aegis apply --session last --file docs/example.md
./zig-out/bin/aegis discard --session last
```

Staged writes are for Aegis-mediated writes. They are not a claim of transparent filesystem interception on every platform.

## MCP Proxy

```sh
./zig-out/bin/aegis mcp inspect --name demo --command python3 -- fixtures/mcp/fake_server.py
python3 fixtures/mcp/fake_client.py | ./zig-out/bin/aegis mcp proxy --name demo --policy policies/presets/mcp-dev.yaml --command python3 -- fixtures/mcp/fake_server.py
```

Aegis mediates newline-delimited stdio MCP messages for launched servers, including tools, resources, prompts, and sampling controls. Remote HTTP MCP and hosted gateway behavior are not v1.1 defaults.

## Red-team

```sh
./zig-out/bin/aegis redteam --ci
./zig-out/bin/aegis redteam --json --ci
```

Fixtures are deterministic, local-only, and synthetic. See [Red-team](docs/redteam.md).

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

## What Aegis Protects

- Child sessions launched through `aegis run`.
- Environment variables passed to those child sessions.
- Aegis-mediated command execution through direct checks and session PATH shims.
- Aegis-mediated staged writes and protected path decisions.
- Stdio MCP servers launched through `aegis mcp proxy`.
- Network destinations that are evaluated by Aegis policy or wrapper/proxy-mediated hooks.
- Persistent audit logs, summaries, and replay output through redaction and hash-chain verification.

## What Aegis Does Not Promise

- Perfect sandboxing.
- Full transparent network enforcement on every platform.
- Full transparent filesystem enforcement on every platform.
- Protection for agents not launched through Aegis.
- Protection from root, admin, kernel, or debugger compromise.
- Protection when a user deliberately approves unsafe actions.
- Safety for arbitrary malicious code or untrusted binaries.

## Why Zig

Aegis needs a small, portable CLI with explicit allocation, predictable binaries, strong cross-platform build control, and a low runtime footprint. Zig fits that shape without adding a managed runtime to every protected agent session.

## Docs

- [Aegis Core package](packages/core/README.md)
- [Aegis CLI package](packages/cli/README.md)
- [Aegis Edge package](packages/edge/README.md)
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
- [Linux platform](docs/platform-linux.md)
- [macOS platform](docs/platform-macos.md)
- [Windows platform](docs/platform-windows.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Release](docs/release.md)

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md), add deterministic tests or fixtures for security-sensitive changes, and run:

```sh
zig build
zig build test
./zig-out/bin/aegis redteam --ci
```

For fixture work, read [Contributing fixtures](docs/contributing-fixtures.md).

## Security Disclosure

Report vulnerabilities privately using [SECURITY.md](SECURITY.md). Do not include real credentials or proprietary logs in reports.
