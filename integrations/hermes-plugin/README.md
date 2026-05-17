# Orca Hermes Plugin

This plugin connects Hermes Agent hooks to the Orca CLI runtime guardrail.

The plugin is a thin bridge. It does not duplicate Orca policy logic, store credentials, run telemetry, or expose MCP/server behavior. Blocking Hermes hook events fail closed when Orca cannot be reached. Informational hooks log a warning and let Hermes continue.

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

The strongest local protection remains running Hermes through `orca run -- hermes ...`, because the wrapper can enforce command-level behavior outside the plugin lifecycle.
