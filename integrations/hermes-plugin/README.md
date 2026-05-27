# Orca Hermes Plugin

This plugin connects Hermes Agent hooks to the Orca CLI runtime guardrail.

The plugin is a thin bridge. It does not duplicate Orca policy logic, store credentials, run telemetry, or expose MCP/server behavior.

## Failure modes

- **`pre_tool_call`**: Fail-closed when Orca is reachable but denies the tool. When Orca is missing, too old for Hermes hooks, or returns a Hermes host mismatch, the default is fail-open with a warning (`ORCA_HERMES_FAIL_OPEN=1`, the default). Set `ORCA_HERMES_FAIL_OPEN=0` to block tool calls until Orca is upgraded.
- **`pre_llm_call`**: Fail-closed only when Orca returns an explicit deny/warn/ask decision. Other Orca failures log a warning and continue without injecting policy context.
- **Informational hooks** (`post_tool_call`, session lifecycle, etc.): Log warnings on Orca failure and never block Hermes.

The strongest local protection remains running Hermes through `orca run -- hermes ...`, because the wrapper can enforce command-level behavior outside the plugin lifecycle.

## Install

From the Orca repository:

```sh
./scripts/install-orca-plugin.sh hermes project
```

Or manually:

```sh
orca plugin install hermes --yes
hermes plugins enable orca
orca plugin doctor hermes
```

The installer copies this directory to `~/.hermes/plugins/orca/` and enables it with `hermes plugins enable orca` when the `hermes` binary is available.

## Hook Coverage

- `pre_tool_call` and `pre_llm_call` are blocking policy checkpoints.
- `on_session_start`, `post_tool_call`, `on_session_end`, `on_session_finalize`, and `on_session_reset` are mapped to Orca lifecycle events.
- `post_llm_call` and `subagent_stop` are informational.
- `pre_gateway_dispatch` is intentionally deferred until the Hermes gateway payload contract is stable.

## Orca discovery

The plugin resolves Orca once per process (cached until `ORCA_BIN` changes), probing candidates in this order:

1. `ORCA_BIN`
2. `./zig-out/bin/orca` (current repo and parents)
3. `~/.local/bin/orca`
4. `~/.orca/bin/orca`
5. `orca` on `PATH`

Only regular files that are executable and pass a Hermes `pre_tool_call` smoke test are selected (exit 0 and hook decision is not `block`, matching `tests/fixtures/hook-safe.json`). `orca plugin doctor` uses a stricter allow-only check on the running Orca binary.

Environment:

- `ORCA_BIN` — force a specific Orca executable (must be executable on disk).
- `ORCA_HERMES_FAIL_OPEN` — `1` (default) allows Hermes tools when Orca is degraded; `0` blocks `pre_tool_call` instead.
