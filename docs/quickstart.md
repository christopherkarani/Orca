# Quickstart (Safe Launch)

Protected agent in a few minutes. Taught path only — no parallel setup/quickstart doors.

## 1. Build Or Install

From a clean checkout:

```sh
./scripts/zig version   # must show 0.16.0
./scripts/zig build
./zig-out/bin/orca version --json
```

The repository is pinned to Zig `0.16.0` (use `./scripts/zig` or `direnv allow` if system `zig` differs). After policy or CLI changes, run `./scripts/test-fast.sh`; run `./scripts/zig build test` before opening a PR. Release installs are covered in [install.md](install.md).

For a package install (Homebrew, install script), see [install.md](install.md), then continue from step 2 with `orca` on your `PATH`.

## 2. Get Protected

```sh
./zig-out/bin/orca start
```

`orca start` is the **only** onboarding door:

- creates `.orca/policy.yaml` when missing (Ask on risk / `generic-agent` preset)
- wires host integrations
- verifies core readiness (daemon + policy)
- prints next steps: run an agent, then `status` / `replay`

Non-interactive / CI-friendly:

```sh
./zig-out/bin/orca start --auto
./zig-out/bin/orca start --auto --hosts claude,codex
```

Public peers `orca setup` and `orca quickstart` are removed — use `orca start`. Power/CI scaffolding may still use advanced commands via `orca help --all`.

## 3. Check Status

```sh
./zig-out/bin/orca status
```

Human output is a traffic light:

| State | Meaning (glance) |
| --- | --- |
| **Protected** | Daemon ready + valid policy |
| **Limited** | Daemon ready but policy missing/invalid |
| **Off** | Daemon unavailable / incompatible |

When not Off, status adds one honest note: mediation covers agents started via Orca; some paths can still bypass. For a deep capability matrix, use `orca doctor` (advanced).

## 4. Run A Protected Agent

Host aliases are the taught launch path:

```sh
./zig-out/bin/orca claude
# or: codex | pi | opencode | openclaw | hermes
```

When a risky action needs approval, interactive sessions offer **Once** / **Always** / **Never** (no rule ids required). Session artifacts land under `.orca/sessions/<session-id>/`.

Custom commands and CI automation still use the advanced run engine (not the day-1 agent launch path):

```sh
./zig-out/bin/orca run -- echo hello
./zig-out/bin/orca run --ci -- ./scripts/agent-task.sh
```

Orca is graded mediation, not a universal sandbox. Absolute paths, non-shimmed binaries, non-proxy traffic, and non-firing host hooks can still bypass. Canonical grades: [compatibility.md](compatibility.md#protection-grades-canonical).

## 5. Replay The Last Session

```sh
./zig-out/bin/orca replay
```

Bare `orca replay` loads the **last** session and highlights denied actions. Useful flags:

```sh
./zig-out/bin/orca replay --only denied
./zig-out/bin/orca replay --verify
./zig-out/bin/orca replay --list
```

`--verify` checks the tamper-evident hash chain. If there are no sessions yet, replay points you back to `orca start` then `orca <agent>`.

## 6. Stop Protection

```sh
./zig-out/bin/orca stop
```

Removes host plugin registrations; binary and policy stay. Restart later with `orca start`.

## 7. Optional: Demo, Dashboard, CI, Red-team

Safe local blocked-action demo (no real damage):

```sh
./zig-out/bin/orca demo blocked-action
./zig-out/bin/orca replay
```

Local dashboard:

```sh
./zig-out/bin/orca dashboard
```

Open `http://127.0.0.1:7742` for health, policy, sessions, and denials. Optional; uses existing CLI/Core paths.

CI readiness and packs (advanced):

```sh
./zig-out/bin/orca policy packs
./zig-out/bin/orca policy apply-pack team-ci --force
./zig-out/bin/orca ci check --format markdown
```

Engine self-test fixtures (not your workspace policy):

```sh
./zig-out/bin/orca redteam --ci
```

Report export is gated to a local Pro/Team license; free mode still allows Safe Launch, policy checks, and replay. See `orca help --all` and [license](../ORCA_CLI_COMMANDS.md) notes.

## Next Steps

- Full CLI surface: `orca help --all`
- Policies: [policy.md](policy.md)
- Dashboard: [dashboard.md](dashboard.md)
- [Leaky-agent demo](../examples/leaky-agent-demo/README.md)
- MCP proxy: [mcp.md](mcp.md)
- Staged writes: [filesystem-staging.md](filesystem-staging.md)
