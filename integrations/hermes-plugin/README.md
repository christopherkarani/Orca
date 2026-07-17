# Orca Hermes Plugin

This plugin connects Hermes Agent hooks to the Orca CLI runtime guardrail.

The plugin is a thin bridge. It does not duplicate Orca policy logic, store credentials, run telemetry, or expose MCP/server behavior.

## Decision → Hermes action (tools)

On `pre_tool_call`, Orca decisions map to Hermes native directives:

| Orca decision | Hermes return | Effect |
|---|---|---|
| `allow` | `None` | Tool proceeds |
| `block` | `{"action":"block","message":...}` | Hard deny; tool does not run |
| `ask` | `{"action":"approve","message":...,"rule_key":...}` | Escalates to Hermes **human approval gate** (`[o]nce` / `[s]ession` / `[a]lways` / `[d]eny`) — approve-and-resume |
| `warn` | log + `None` | Advisory warning only; tool proceeds (not collapsed to block) |
| other / malformed | `{"action":"block",...}` | Fail-closed |

### Approve-and-resume (`ask`)

Hermes ≥ the version that shipped `pre_tool_call` `action: approve` (escalation to the same gate Tier-2 dangerous commands use) is required for the native path. When Orca returns `ask`:

1. The plugin returns `{"action":"approve","message":...,"rule_key":...}`.
2. Hermes prompts the user (CLI/TUI) or submits a pending approval (gateway).
3. On approve, the tool **resumes** and runs. On deny/timeout, Hermes fail-closes to a block.

This is **not** a passive model note, and it is **not** “tell the model to call `clarify`”. Enforcement is host-native.

#### `rule_key` grain

Always-allow entries are keyed so they do not over-approve:

```text
orca:{rule_id|policy}:{tool_name}:{sha256(args)[:12]}
```

Approving `curl http://a.example` under rule `core.shell:network` does **not** auto-approve a later `curl http://b.example` under the same rule.

### CI / noninteractive

When `CI`, `ORCA_CI`, or `ORCA_NONINTERACTIVE` is set truthily, Orca `ask` is hardened to Hermes `block` (no approval prompt). Hermes also fail-closes plugin-escalated approvals in non-interactive non-gateway contexts.

## Failure modes

- **`pre_tool_call`**: Uses the mapping above. When Orca is missing, too old for Hermes hooks, or returns a Hermes host mismatch, the default is fail-open with a warning (`ORCA_HERMES_FAIL_OPEN=1`, the default). Set `ORCA_HERMES_FAIL_OPEN=0` to block tool calls until Orca is upgraded.
- **`pre_llm_call`**: **Context-only** — Hermes cannot veto the turn or open an approval dialog on this hook. Orca `warn` / `context_only` inject advisory notes. Orca `ask` and `block` inject **honest** notes that do **not** claim enforcement or auto-triggered approval; the strongest real gate for prompts remains `orca run -- hermes ...`. Other Orca failures log a warning and continue without injecting policy context.
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

- `pre_tool_call` is the tool policy gate: hard `block`, native `approve` for `ask`, advisory log for `warn`.
- `pre_llm_call` is context-only and is **not** an enforcement or approval path (see above).
- `on_session_start`, `post_tool_call`, `on_session_end`, `on_session_finalize`, and `on_session_reset` are mapped to Orca lifecycle events.
- `post_llm_call` and `subagent_stop` are informational.
- `pre_gateway_dispatch` is intentionally deferred until the Hermes gateway payload contract is stable.

## Telegram and Discord (gateway)

Hermes versions that honor hook return values apply `pre_tool_call` directives in gateway sessions:

- **`block`**: Denied tools do not execute. Hermes reports the plugin block to the agent as a tool failure.
- **`ask` → `approve`**: Escalates through Hermes’ gateway approval path (pending approval / platform buttons where supported). Exact UX varies by Hermes version and platform adapter; Orca does not fake a dialog.
- **`warn`**: Advisory only (tool proceeds after a log line).

Limitations (honest):

- Gateway approval UX depends on Hermes (buttons, `/approve`, etc.). If the gateway path cannot present a prompt, Hermes fail-closes the plugin-escalated approval rather than silently running the tool.
- The exact Orca reason text is not guaranteed to appear verbatim in the Telegram or Discord message body.
- Prompt-level `ask`/`block` still cannot be gated by this plugin alone — use `orca run -- hermes` for outer enforcement.

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
- `CI` / `ORCA_CI` / `ORCA_NONINTERACTIVE` — when truthy, harden Orca `ask` on tools to Hermes `block`.

## Manual verification (CLI approve UI)

1. Install/enable the plugin and point `ORCA_BIN` at a Hermes-capable Orca build.
2. Run Hermes interactively so a policy `ask` tool fires (or temporarily configure a policy that returns `ask` for a known tool).
3. Confirm Hermes shows the once/session/always/deny approval UI — not a permanent block error with no resume.
4. Approve once → tool runs. Deny → tool blocked. Always → subsequent identical args under the same `rule_key` skip the prompt.
5. Export `CI=1` and confirm the same `ask` becomes a hard block without a prompt.
