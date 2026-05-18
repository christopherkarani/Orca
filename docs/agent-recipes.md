# Agent Recipes

These are starting points. Agent-specific presets are generic unless their policy file says otherwise.

## Generic Coding Agent

```sh
./zig-out/bin/orca init --preset generic-agent
./zig-out/bin/orca run -- <agent-command>
```

## MCP Development

```sh
./zig-out/bin/orca run --policy policies/presets/mcp-dev.yaml -- <agent-command>
./zig-out/bin/orca mcp inspect --name demo --command python3 -- fixtures/mcp/fake_server.py
```

## Strict Local Mode

```sh
./zig-out/bin/orca run --policy policies/presets/strict-local.yaml --mode strict -- <agent-command>
```

## Trusted Local Mode

Use only for code and commands you already trust:

```sh
./zig-out/bin/orca run --policy policies/presets/trusted-local.yaml --mode trusted -- <agent-command>
```

## No-network Mode

```sh
./zig-out/bin/orca run --no-network -- <agent-command>
```

This updates Orca network policy decisions and environment metadata. It is not transparent network blocking unless `orca doctor` reports an active backend.

## Secretless Runtime

```sh
./zig-out/bin/orca credentials check
./zig-out/bin/orca run --secretless --network-backend proxy -- <agent-command>
```

This strips raw secret-like environment values from the child process and uses broker references instead. Orca records policy, redaction, and proxy request decision evidence, but it is not a vault and does not inject credentials into the child environment. Proxy mode is explicit and loopback-only; HTTPS policy is host/port-only unless a cooperative hook supplies method/path metadata.

## CI Mode

```sh
./zig-out/bin/orca run --mode ci -- zig build test
./zig-out/bin/orca redteam --ci
```

## Staged Write Review

```sh
./zig-out/bin/orca diff --session last
./zig-out/bin/orca apply --session last
./zig-out/bin/orca discard --session last
```

## Preset Notes

Presets exist for `claude-code`, `codex`, `cursor-agent`, `opencode`, `cline-roo`, `mcp-dev`, `github-actions`, `strict-local`, and `trusted-local`. They are local policy templates, not integrations with vendor services.
