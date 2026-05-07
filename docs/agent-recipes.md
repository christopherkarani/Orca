# Agent Recipes

These are starting points. Agent-specific presets are generic unless their policy file says otherwise.

## Generic Coding Agent

```sh
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis run -- <agent-command>
```

## MCP Development

```sh
./zig-out/bin/aegis run --policy policies/presets/mcp-dev.yaml -- <agent-command>
./zig-out/bin/aegis mcp inspect --name demo --command python3 -- fixtures/mcp/fake_server.py
```

## Strict Local Mode

```sh
./zig-out/bin/aegis run --policy policies/presets/strict-local.yaml --mode strict -- <agent-command>
```

## Trusted Local Mode

Use only for code and commands you already trust:

```sh
./zig-out/bin/aegis run --policy policies/presets/trusted-local.yaml --mode trusted -- <agent-command>
```

## No-network Mode

```sh
./zig-out/bin/aegis run --no-network -- <agent-command>
```

This updates Aegis network policy decisions and environment metadata. It is not transparent network blocking unless `aegis doctor` reports an active backend.

## CI Mode

```sh
./zig-out/bin/aegis run --mode ci -- zig build test
./zig-out/bin/aegis redteam --ci
```

## Staged Write Review

```sh
./zig-out/bin/aegis diff --session last
./zig-out/bin/aegis apply --session last
./zig-out/bin/aegis discard --session last
```

## Preset Notes

Presets exist for `claude-code`, `codex`, `cursor-agent`, `opencode`, `cline-roo`, `mcp-dev`, `github-actions`, `strict-local`, and `trusted-local`. They are local policy templates, not integrations with vendor services.
