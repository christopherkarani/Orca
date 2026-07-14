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

## Day-1 coding agents (Claude / Pi / Codex)

**Usable model credentials today:** omit `--secretless`. Launch under process wrap so env filtering, command policy, and audit apply, while env-based API keys (or the host’s own login store) can still authenticate.

```sh
./zig-out/bin/orca init --preset generic-agent
# or: --preset claude-code | codex | …
./zig-out/bin/orca run -- <agent-command>
# examples:
#   orca run -- claude
#   orca run -- pi
#   orca run -- codex
```

Notes:

- Prefer the agent host’s built-in login/session credentials when available; those do not depend on raw `*_API_KEY` env vars surviving the child filter.
- In `strict` / `ci` / `redteam`, secret-like env is stripped unless policy allows it — model keys in env will not be present even without `--secretless`.
- Plugin/hooks alone are not secretless and are not process wrap; strongest local protection remains `orca run -- <agent-command>`.

## Secretless Runtime (opt-in only)

**Not ready — do not default** for day-1 agent launches that need model API keys from the environment. Secretless always rewrites secret-like env to non-resolving `orca-secret://local-dummy/…` references. Claude, Pi, Codex, and similar hosts do not resolve those refs, so providers typically fail auth (for example 401). When rewrites occur, `orca run` prints a stderr warning — see [credentials.md](credentials.md) § Secretless Mode.

```sh
./zig-out/bin/orca credentials check
./zig-out/bin/orca run --secretless --network-backend proxy -- <command>
```

This strips raw secret-like environment values from the child process and substitutes broker **references**. Orca records policy, redaction, and proxy request decision evidence, but it is not a vault and does **not** inject usable credentials into the child environment or into HTTPS to model providers. Proxy mode is explicit and loopback-only; HTTPS policy is host/port-only unless a cooperative hook supplies method/path metadata.

Use secretless for deliberate strip/demo workflows, not as the default agent launch path until env broker injection/resolution is product-ready.

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
