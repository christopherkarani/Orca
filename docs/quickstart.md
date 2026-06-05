# Quickstart

## 1. Build Or Install

From a clean checkout:

```sh
./scripts/zig version   # must show 0.16.0
./scripts/zig build
./zig-out/bin/orca version --json
```

The repository is pinned to Zig `0.16.0` (use `./scripts/zig` or `direnv allow` if system `zig` differs). After policy or CLI changes, run `./scripts/test-fast.sh`; run `./scripts/zig build test` before opening a PR. Release installs are covered in [install.md](install.md).

## 2. Initialize A Policy

```sh
./zig-out/bin/orca init --preset generic-agent
./zig-out/bin/orca policy check .orca/policy.yaml
```

Review the generated policy before using it for real work.

The policy created by `init --preset generic-agent` (and `setup --auto`) is tuned for local coding agents: common dev commands (including plain `curl`, not `curl | sh`) are allowed, pipe-to-shell and `rm -rf` stay denied, and network egress defaults to `ask` with curated allow/ask hosts. Broad read protections for shell histories/browser data/macOS Library paths, staged writes, and explicit deny for `.git/**` and `.orca/**` (bare and `./` forms) remain. Edit `.orca/policy.yaml` for your workflow. Use `orca policy explain command 'your cmd'` and `orca policy explain network api.openai.com` to explore decisions.

## 3. Check Local Capabilities

```sh
./zig-out/bin/orca doctor
```

`doctor` is the source of truth for whether a feature is `active`, `partial`, `wrapper-only`, `observe-only`, `limited`, or `unavailable` on your platform.

## 4. Run A Protected Command

```sh
./zig-out/bin/orca run -- echo hello
```

Orca writes audit artifacts under `.orca/sessions/<session-id>/`.

## 5. Replay The Session

```sh
./zig-out/bin/orca replay --session last
./zig-out/bin/orca replay --session last --verify
./zig-out/bin/orca replay --session last --only denied --verify
```

`--verify` checks the tamper-evident hash chain.

## 6. Export A Local Safety Report

Report export is gated to a local Pro/Team license. Development builds include offline test licenses so the product gate can be exercised without a hosted service:

```sh
./zig-out/bin/orca license status
./zig-out/bin/orca license activate dev-pro
./zig-out/bin/orca report --session last --format markdown
```

Free mode still allows `orca run`, policy checks, and basic replay.

## 7. Check CI Readiness

```sh
./zig-out/bin/orca policy packs
./zig-out/bin/orca policy apply-pack team-ci --force
./zig-out/bin/orca ci check --format markdown
```

`orca ci check` validates `.orca/policy.yaml`, rejects dangerous obvious defaults, and runs a focused CI-safe red-team fixture.
Packaged installs use `ORCA_RESOURCE_ROOT` to find those fixtures when the command runs outside the source checkout.

## 8. Try Demo Mode

```sh
./zig-out/bin/orca demo blocked-action
./zig-out/bin/orca replay --session last --only denied --verify
```

The demo creates safe local audit evidence for a blocked destructive command. It does not execute the command.

## 9. Open The Local Dashboard

```sh
./zig-out/bin/orca dashboard
```

Open `http://127.0.0.1:7742` to inspect health, policy status, OpenClaw/Hermes setup, recent sessions, and denied actions. The dashboard is optional and uses existing Orca CLI/Core paths.

## 10. Run Red-team Fixtures

```sh
./zig-out/bin/orca redteam --ci
```

The suite is deterministic and uses synthetic fixtures only.

## Next Steps

- Learn policies in [policy.md](policy.md).
- Use the local dashboard with [dashboard.md](dashboard.md).
- Run the local [leaky-agent demo](../examples/leaky-agent-demo/README.md).
- Proxy an MCP server with [mcp.md](mcp.md).
- Review staged writes with [filesystem-staging.md](filesystem-staging.md).
