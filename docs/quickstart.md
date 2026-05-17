# Quickstart

## 1. Build Or Install

From a clean checkout:

```sh
zig version
zig build
./zig-out/bin/orca version --json
```

The repository is pinned to Zig `0.15.2`. Release installs are covered in [install.md](install.md).

## 2. Initialize A Policy

```sh
./zig-out/bin/orca init --preset generic-agent
./zig-out/bin/orca policy check .orca/policy.yaml
```

Review the generated policy before using it for real work.

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
```

`--verify` checks the tamper-evident hash chain.

## 6. Run Red-team Fixtures

```sh
./zig-out/bin/orca redteam --ci
```

The suite is deterministic and uses synthetic fixtures only.

## Next Steps

- Learn policies in [policy.md](policy.md).
- Run the local [leaky-agent demo](../examples/leaky-agent-demo/README.md).
- Proxy an MCP server with [mcp.md](mcp.md).
- Review staged writes with [filesystem-staging.md](filesystem-staging.md).
