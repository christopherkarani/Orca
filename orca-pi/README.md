# @orca-sec/pi-orca

Official Orca integration package for Pi. It intercepts Pi `bash` tool calls and evaluates shell commands with:

```bash
orca evaluate --json --stdin
```

Safe commands proceed. Denied commands are blocked before Pi runs them. Orca errors follow the configured unavailable-mode policy.

## Prerequisites

- Pi installed.
- Node.js 22.19 or newer.

## Install

```bash
pi install npm:@orca-sec/pi-orca
```

This installs the matching `@orca-sec/orca` CLI and daemon dependency. Do not mix `pi install ./orca-pi` with `pi install npm:@orca-sec/pi-orca`; remove one source before switching to avoid duplicate extension registration and binary ambiguity.

Local development or validation:

```bash
pi install ./orca-pi
pi -e ./orca-pi
```

## First Run

No per-session command is required. On session start, the extension quietly creates `.orca/policy.yaml` with the `generic-agent` preset when it is missing, then probes Orca health. The first protected bash call waits for this bootstrap while Pi startup remains non-blocking.

Run `/orca-setup` to repeat the Pi-only policy and health setup manually. It does
not run `orca start` or install plugins for other agent hosts.

Use `/orca-stop` to disable Orca protection for the current Pi session, and
`/orca-start` to re-enable it and verify Pi-only policy/health setup. These
commands only affect the in-memory Pi session; they do not uninstall the package,
remove policies, or start/stop other host plugins.

## Behavior

- Non-`bash` tool calls are ignored.
- `bash` tool calls are sent to Orca as JSON over stdin.
- Orca `allow` lets the tool proceed.
- Orca `deny` returns `{ block: true, reason }` to Pi.
- Orca `error`, malformed JSON, spawn failures, or timeouts use the configured unavailable mode.

Unavailable modes:

- `auto`: interactive Pi sessions ask; noninteractive/json/print sessions block.
- `ask`: prompt with Block, Run once anyway, Disable Orca for this session, or Show repair instructions.
- `noninteractive-block`: block and show repair guidance.
- `strict`: always block on Orca errors.
- `allow-with-warning`: allow but warn that Orca is degraded.

Change mode in Pi:

```text
/orca-mode
/orca-mode strict
/orca-mode allow-with-warning
/orca-mode bypass on
/orca-mode bypass off
```

Session bypass is in-memory only. It is cleared when the Pi session shuts down or
reloads. `/orca-stop` turns this bypass on; `/orca-start` turns it off and reruns
the Pi health check.

The status line reports `orca ready`, `orca missing`, `orca degraded`, or `orca bypass`.

Set `ORCA_PI_AUTO_SETUP=false` to disable session bootstrap. The package-managed runtime is used by default; set `ORCA_PI_USE_PATH=true` only when you explicitly trust a compatible PATH installation. `ORCA_BIN=/absolute/path/to/orca` remains the highest-priority override when the file is executable.

## Troubleshooting

Orca not found:

- Reinstall `npm:@orca-sec/pi-orca` so its version-locked runtime dependency can provision both binaries.
- If overriding package resolution, confirm `ORCA_BIN` points to an executable Orca binary.

Daemon unavailable:

- Run `/orca-setup`, then `/orca-doctor`.
- The daemon normally starts automatically on the first `orca evaluate` call.

Protocol incompatible:

- Update Orca and rerun `/orca-doctor`.
- The extension fails closed by default in noninteractive mode.

Command unexpectedly blocked:

- Read the Orca reason.
- Do not rewrite the command to bypass Orca.
- Ask the user whether to use an Orca allowlist or an explicit allow-once flow.

## Security Notes

- The extension does not execute the agent's bash command while evaluating it.
- Orca is invoked with `spawn(file, args, { shell: false })`; no shell interpolation is used.
- Request JSON is passed through stdin.
- Raw commands are not logged by default.
- Block messages use Orca's redacted reason and basic token redaction.
- Noninteractive mode fails closed by default.
- Session bypass is not persisted.
- Session bypass is keyed to the Pi session id when Pi exposes one.
- Malformed `bash` tool-call payloads fail closed.
- Child process output is bounded before parsing.
- The extension does not modify Pi tool input.
- Non-bash tools are not blocked.

## Version Compatibility

This package targets Pi packages using `pi.extensions` / `pi.skills` manifests and Pi extension APIs with `tool_call`, `registerCommand`, `ctx.cwd`, `ctx.mode`, and `ctx.hasUI`.

It targets Orca CLI builds exposing `orca evaluate --json --stdin` with schema version `1` and decisions `allow`, `deny`, or `error`.

## Known Limitations

- Slash commands (`/orca-setup`, `/orca-start`, `/orca-stop`, `/orca-doctor`,
  `/orca-mode`) are registered at extension load time. In Pi noninteractive,
  print, or json modes, command output may not be visible even when registration
  succeeds. Validate slash commands in an interactive Pi session or via unit
  tests.
- Session bypass is in-memory only and clears when the Pi session ends or reloads.
- Only Pi `bash` tool calls are evaluated. Other tools (for example `read`) are not intercepted.

## Smoke Test Checklist

1. `./zig-out/bin/orca evaluate --json --stdin` allows `git status`.
2. `./zig-out/bin/orca evaluate --json --stdin` denies `rm -rf /`.
3. `./zig-out/bin/orca evaluate --json --stdin` returns exit `64` for invalid schema.
4. `cd orca-pi && npm test`.
5. `cd orca-pi && npm pack --dry-run`.
6. `pi -e ./orca-pi`.
7. Safe bash tool call proceeds.
8. Dangerous bash tool call blocks.
9. Orca unavailable interactive mode asks.
10. Orca unavailable noninteractive mode blocks.
11. `/orca-setup`, `/orca-start`, `/orca-stop`, `/orca-doctor`, and `/orca-mode` work.
12. `pi install ./orca-pi`.
13. `pi list` shows `@orca-sec/pi-orca` or the local package source.
