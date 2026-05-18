# Orca

Orca is a local runtime guardrail for AI agents.

It helps developers run tools like OpenClaw, Hermes, Codex, Claude Code, and OpenCode with local policies for commands, files, environment variables, network targets, and tool calls. Orca is not an AI agent. It is the safety layer around the agent.

Use Orca when you want to answer practical questions:

- Can this agent run `rm -rf`, `sudo`, or `curl | sh`?
- Can it read `.env`, SSH keys, cloud credentials, or tokens?
- Which actions did Orca block?
- Can I replay what happened after an agent session?
- Can my team share the same local guardrails in a repo?

The strongest protection is running the agent through `orca run`. Host plugins add native hooks inside supported agent hosts, but they do not replace the runtime wrapper.

## Quick Start

Build or install Orca, then check that the CLI works:

```bash
zig build
./zig-out/bin/orca doctor
```

If `orca` is already on your `PATH`, use `orca` instead of `./zig-out/bin/orca`.

Create a policy in your repo:

```bash
orca init --preset generic-agent
orca policy check .orca/policy.yaml
```

Run an agent through Orca:

```bash
orca run -- openclaw
orca run -- hermes
```

After a session, see what Orca prevented:

```bash
orca replay --session last --only denied --verify
```

Create a sellable local report after activating a local Pro/Team license:

```bash
orca license activate dev-pro
orca report --session last --format markdown
```

For CI and policy packs:

```bash
orca policy packs
orca policy apply-pack team-ci --force
orca ci check --format markdown
```

To see value without running a destructive command:

```bash
orca demo blocked-action
orca replay --session last --only denied --verify
```

## OpenClaw

For the simplest strong protection:

```bash
orca init --preset generic-agent
orca run -- openclaw
```

To add OpenClaw-native hooks:

```bash
openclaw plugins install clawhub:orca-openclaw-plugin
orca plugin doctor openclaw
```

If your OpenClaw version does not support ClawHub installs, use:

```bash
openclaw plugins install npm:orca-openclaw-plugin
```

The OpenClaw plugin sends lifecycle events to Orca. The important blocking checkpoints are `tool.before` and `permission.before`, so Orca can stop a tool call or deny a permission request before OpenClaw proceeds.

Detailed setup: [OpenClaw integration](docs/integrations/openclaw.md)

## Hermes

For the simplest strong protection:

```bash
orca init --preset generic-agent
orca run -- hermes
```

To add Hermes-native hooks:

```bash
orca plugin install hermes --yes
hermes plugins enable orca
orca plugin doctor hermes
```

The Hermes plugin maps `pre_tool_call` and `pre_llm_call` to blocking Orca policy checkpoints. Session start/end and post-call events are informational.

Detailed setup: [Hermes plugin](integrations/hermes-plugin/README.md)

## Policies

Orca policies live in:

```text
.orca/policy.yaml
```

Start with a preset:

```bash
orca init --preset generic-agent
```

Then edit the policy for your repo. A typical command policy looks like this:

```yaml
mode: ask

commands:
  default: ask
  allow:
    - "git status"
    - "git diff *"
    - "zig build *"
  deny:
    - "rm -rf *"
    - "sudo *"
    - "curl * | sh"
    - "cat .env"

files:
  read:
    deny:
      - "./.env"
      - "~/.ssh/**"
      - "**/*token*"
  write:
    deny:
      - "./.git/**"
      - "./.orca/**"
```

Policy modes:

- `observe`: log decisions with minimal blocking.
- `ask`: ask for risky actions when interactive.
- `strict`: block more aggressively.
- `ci`: never prompt; `ask` becomes block.

Validate changes with:

```bash
orca policy check .orca/policy.yaml
```

Policy reference: [Policy docs](docs/policy.md)

## Reviewing Blocked Actions

Orca writes session artifacts under:

```text
.orca/sessions/<session-id>/
```

The fastest way to see prevented actions is:

```bash
orca replay --session last --only denied --verify
```

For a Pro/Team local product artifact:

```bash
orca report --session last --format markdown
```

Use JSON output for automation:

```bash
orca replay --session last --only denied --json
```

Replay shows the session, command, policy, status, denied events, and hash-chain verification. Secret-like values are redacted before persistence.

Replay reference: [Replay docs](docs/replay.md)

## Local Dashboard

Start the localhost dashboard when you want the same local state in a GUI:

```bash
orca dashboard
```

Then open `http://127.0.0.1:7742`. The dashboard shows health, local license status, CI readiness, policy packs, OpenClaw/Hermes readiness, recent sessions, prevented actions, report/demo actions, and fixed quick actions backed by Orca CLI/Core paths. It does not replace `orca run`, does not add cloud services, and does not evaluate policies in browser code.

Dashboard reference: [Local dashboard docs](docs/dashboard.md)

## Other Agent Hosts

Orca also includes integrations for Codex, Claude Code, and OpenCode:

```bash
orca run -- codex
orca run -- claude
orca run -- opencode
```

Plugin docs:

- [Codex](docs/integrations/codex.md)
- [Claude Code](docs/integrations/claude-code.md)
- [OpenCode](docs/integrations/opencode.md)
- [OpenClaw](docs/integrations/openclaw.md)
- [Hermes](integrations/hermes-plugin/README.md)

## Security Model

Orca is local-first and policy-driven. It provides runtime wrapping, host hook adapters, secret redaction, audit logs, replay, and red-team checks.

Orca does not promise perfect sandboxing. It does not protect agents launched outside Orca, and host plugins are limited by each host's hook system. For the strongest local protection, run the agent process itself through:

```bash
orca run -- <agent-command>
```

Check your platform capabilities with:

```bash
orca doctor
```

## Documentation

- [Install](docs/install.md)
- [Quickstart](docs/quickstart.md)
- [Policy](docs/policy.md)
- [Replay](docs/replay.md)
- [Commands](docs/commands.md)
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)
- [Aegis to Orca migration](docs/migration-aegis-to-orca.md)

Edge is a separate simulation/SITL/customer-evaluation workstream. It is not real-flight readiness, certification, detect-and-avoid, or an autopilot replacement. See [Edge docs](docs/edge/README.md).

## Development

```bash
zig build
zig build test
./zig-out/bin/orca --help
./zig-out/bin/orca redteam --ci
```
