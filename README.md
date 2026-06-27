# Orca &nbsp;[![Version](https://img.shields.io/badge/version-1.2.3-blue)](https://github.com/christopherkarani/Orca/releases) [![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE) [![Zig](https://img.shields.io/badge/built%20with-Zig-orange)](https://ziglang.org) [![Build](https://img.shields.io/github/actions/workflow/status/christopherkarani/Orca/build.yml?branch=main&label=build)](https://github.com/christopherkarani/Orca/actions/workflows/build.yml) [![Stars](https://img.shields.io/github/stars/christopherkarani/Orca?style=social)](https://github.com/christopherkarani/Orca)

**Unleash AI agents with confidence.**

You type: *"Clean up my repo."*  
Your AI agent thinks: `rm -rf *`  
**Orca blocks it before it happens.**

Orca wraps the AI tools you already use—Codex, Claude Code, OpenCode, OpenClaw, Hermes—and enforces local rules for commands, files, environment variables, and network calls. It is not an AI agent. It is the safety layer that lets you delegate to one

```bash
# Install (macOS/Linux)
brew tap christopherkarani/orca && brew install --formula orca

# Or install with the official script
curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh

# Or build both required binaries from source (Zig 0.16.0 + Rust)
./scripts/build-all.sh
```

---

## Local dashboard

Start the web UI for a visual view of sessions, policy status, and prevented actions:

```bash
orca dashboard
```

Then open [http://127.0.0.1:7742](http://127.0.0.1:7742). The dashboard is entirely local—no cloud services, no browser-side policy evaluation.

![Orca Dashboard Overview](https://raw.githubusercontent.com/christopherkarani/Orca/main/docs/images/dashboard-overview.png)

The dashboard shows live stats (version, policy validity, secretless mode, license), quick actions, and a feed of recently prevented actions with full verification status.

---

## See it in 30 seconds

```bash
# 1. Check that Orca is ready
orca doctor

# 2. Initialize a policy
orca init --preset generic-agent

# 3. Watch Orca block a dangerous command—safely
orca demo blocked-action

# 4. Review exactly what was prevented
orca replay --session last --only denied --verify
```

No AI agent required for the demo. No files are harmed

---

## Before Orca → After Orca

| Without Orca | With Orca |
|---|---|
| You babysit every AI suggestion, afraid of `rm -rf` | You delegate. Orca intercepts and blocks the bad ones |
| You have no idea what the agent actually did | You replay the full session—allowed, denied, and asked |
| You copy `.env` into the agent context by accident | [Orca redacts secrets](#credential-guardrails) before they reach the agent |
| Your team has no shared rules | Commit `.orca/policy.yaml`—everyone runs under the same guardrails |
| You discover damage after the fact | You see the block in real time, before anything happens |

---

## Three ways people use Orca

**1. Solo developer using Claude Code or Codex**
```bash
orca run -- claude
# Now code with confidence. Orca asks before risky actions.
```

**2. Team lead standardizing AI tool usage**
```bash
# Commit a policy to your repo
cat .orca/policy.yaml
# Everyone who clones the repo runs under the same rules automatically
```

**3. CI pipeline running autonomous benchmarks**
```bash
orca run --ci -- codex --prompt "Refactor the auth module"
# Non-interactive. No prompts. Dangerous actions are blocked, not asked.
```

---

## What Orca does

AI agents can run shell commands, read files, and make network requests on your behalf. That is powerful—and risky. Orca gives you four things:

1. **Block dangerous actions before they happen**  
   Stop `rm -rf`, `sudo`, `curl | sh`, or reading `.env` and SSH keys.

2. **Replay and audit sessions**  
   After an agent finishes, see exactly what it tried to do, what was allowed, and what was denied. Evidence is tamper-evident and locally stored.

3. **Share team guardrails**  
   Commit `.orca/policy.yaml` to your repo so everyone on your team runs under the same rules.

4. **Protect API Keys and Env Variables**

---

## Quick Start

### Already installed? Skip to step 2.

```bash
# macOS
brew tap christopherkarani/orca
brew install --formula orca

# Linux (amd64 / arm64)
curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh
```

> The script installs to `~/.local/bin` and automatically adds it to your shell's `PATH`. Open a new terminal (or run `source ~/.zshrc` / `.bashrc`) to use `orca` right away.
>
> **Prefer to build?** See [docs/install.md](docs/install.md) for source builds, Windows installers, and Docker.

After installing, verify:

```bash
orca doctor
```

### 1. Create your first policy

```bash
orca init --preset generic-agent
```

This creates `.orca/policy.yaml` in the current directory:

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

files:
  read:
    deny:
      - "./.env"
      - "~/.ssh/**"
      - "**/*token*"
```

- `mode: ask` — Orca asks you before risky actions when you are interactive.
- `mode: strict` — Block more aggressively.
- `mode: observe` — Log decisions with minimal blocking.
- `mode: ci` — Never prompt; `ask` becomes block. Ideal for automation.

Validate it:

```bash
orca policy check .orca/policy.yaml
```

### 2. Run an agent with guardrails

```bash
orca run -- codex
orca run -- claude
orca run -- opencode
orca run -- openclaw
orca run -- hermes
```

Orca launches the agent as a child process, intercepts its tool calls, and enforces your policy in real time.

### 3. Review a session

After the agent exits:

```bash
# See everything that was denied
orca replay --session last --only denied --verify

# Export a report (requires local Pro/Team license)
orca license activate dev-pro
orca report --session last --format markdown

# JSON output for automation
orca replay --session last --only denied --json
```

Session artifacts live under `.orca/sessions/<session-id>/`.

---

## How it works

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│   You       │ ──▶  │    Orca      │ ──▶  │   AI Agent      │
│             │      │  (wrapper)   │      │ (Codex, etc.)   │
└─────────────┘      └──────────────┘      └─────────────────┘
                            │                        │
                            │                      tool call
                            │                        ▼
                     ┌──────────────┐      ┌─────────────────┐
                     │  Policy      │ ◀──  │  Tool / File /  │
                     │  engine      │      │  Network req    │
                     └──────────────┘      └─────────────────┘
                            │
                    allow / deny / ask
```

The strongest protection is the `orca run` wrapper, because Orca controls the agent process directly. Orca also offers host plugins for deeper integration with specific agents, but plugins are limited by each host's hook system. For maximum safety, always run the agent through `orca run`.

---

## Supported agents

| Agent | One-line guardrails |
|-------|---------------------|
| **Codex** | `orca run -- codex` |
| **Claude Code** | `orca run -- claude` |
| **OpenCode** | `orca run -- opencode` |
| **OpenClaw** | `orca run -- openclaw` |
| **Hermes** | `orca run -- hermes` |

Optional native plugins offer deeper integration. See [docs/integrations/](docs/integrations/) per agent.

---

## Native plugin install

### Hermes (copy-paste)

Copy and paste this prompt into Hermes to install the Orca plugin:

```
Install the Orca plugin for runtime guardrails. Run: orca plugin install hermes --yes
```

Or install manually:

```bash
# From the Orca repo root
./scripts/install-orca-plugin.sh hermes project

# Or directly
orca plugin install hermes --yes
hermes plugins enable orca
orca plugin doctor hermes
```

The Hermes plugin is a Python bridge that calls the Orca CLI via `subprocess`. It does not trigger any security scanners and installs cleanly.

### OpenClaw (copy-paste)

Copy and paste this prompt into OpenClaw to install the Orca plugin:

```
Install the Orca OpenClaw plugin with the security scan override: openclaw plugins install npm:orca-openclaw-plugin --dangerously-force-unsafe-install
```

#### Why the override is needed

OpenClaw's security scanner blocks any plugin that uses `child_process` (e.g., `execSync`, `spawn`). The Orca plugin legitimately needs this to call the `orca` CLI binary for policy enforcement. There is currently no way to declare this permission in the plugin manifest.

**Install commands:**

```bash
# npm (recommended)
openclaw plugins install npm:orca-openclaw-plugin --dangerously-force-unsafe-install

# Or from ClawHub
openclaw plugins install clawhub:orca-openclaw-plugin --dangerously-force-unsafe-install

# Or local path (if you have the Orca repo cloned)
openclaw plugins install ./integrations/openclaw-plugin --dangerously-force-unsafe-install
```

> **Note:** The `--dangerously-force-unsafe-install` flag is required because OpenClaw's heuristic scanner cannot distinguish legitimate process spawning from malicious code. The Orca plugin only calls the local `orca` binary that you already trust.

For a deep analysis of this issue and long-term fix options, see [docs/integrations/openclaw-security-scan-analysis.md](docs/integrations/openclaw-security-scan-analysis.md).

---

## Credential Guardrails

Orca protects your credentials, API keys, and secrets through **eight layers of defense**:

1. **Secret Detection Engine** — Pattern matching for API keys, tokens, JWTs, and passwords
2. **Environment Filtering** — Strips secrets before they reach the agent process
3. **Credential Brokers** — Secure resolution via 1Password, macOS Keychain, or env files
4. **Policy Validation** — Rejects unsafe credential configurations
5. **Network Scanning** — Blocks secrets in URLs and detects exfiltration attempts
6. **Command Classification** — Denies `cat .env`, `cat ~/.ssh/id_ed25519`, and similar
7. **File System Guards** — Blocks access to `.env`, SSH keys, and credential stores
8. **Audit Redaction** — Secrets are redacted before any log is written to disk

### What is detected

Orca automatically detects and protects:

- **GitHub tokens** (classic PAT prefix and `github_pat_` patterns)
- **OpenAI API keys** (provider secret keys with the standard OpenAI prefix)
- **Anthropic API keys** (provider secret keys with the standard Anthropic prefix)
- **AWS access keys** (`AKIA...`, `ASIA...`)
- **JWTs** (three-part base64 tokens)
- **PEM/SSH private keys**
- **High-entropy strings** (generic API keys)
- **Cloud credential JSON** (Google service accounts)

### Secretless mode

Run with `--secretless` to replace secret values with broker references:

```bash
orca run --secretless -- codex
```

In this mode, `GITHUB_TOKEN=<github-pat>` becomes `GITHUB_TOKEN=orca-secret://local-dummy/env/GITHUB_TOKEN/a1b2c3d4`. The agent sees the reference, not the raw value.

### Credential brokers

Orca supports secure credential resolution without exposing raw values:

```yaml
credentials:
  default_broker: onepassword
  brokers:
    onepassword:
      type: 1password-cli
      account: my-team
    env_dev:
      type: env-file-dev
      path: .orca/dev-secrets.env
  refs:
    github_pat:
      broker: onepassword
      ref: "op://Engineering/GitHub PAT/token"
```

Supported brokers: `local-dummy`, `env-file-dev`, `1password-cli`, `macos-keychain`, `infisical-agent-vault`.

**Full details**: [docs/credentials.md](docs/credentials.md)

---

## Policy reference

Policies live in `.orca/policy.yaml`. Key sections:

| Section | Controls |
|---------|----------|
| `commands` | Shell commands the agent can run |
| `files` | File read/write access |
| `network` | Outbound HTTP/HTTPS requests |
| `credentials` | Secret broker configuration |
| `services` | Service-scoped network rules (host, method, path) |

Full reference: [docs/policy.md](docs/policy.md)

---

## Security model

- **Local-first** — All policy decisions, audit logs, and replay evidence stay on your machine.
- **Policy-driven** — You write the rules; Orca enforces them.
- **Tamper-evident** — Session logs include hash-chain verification.
- **Secret redaction** — Sensitive values are redacted before persistence. See [Credential Guardrails](#credential-guardrails) for details.
- **Fails closed** — If the network proxy fails during a run, Orca terminates the child process.

Orca does not promise perfect sandboxing. It protects agents launched *through* Orca. Agents started outside the wrapper are not covered.

Run `orca doctor` to check your platform capabilities.

---

## Documentation

- [Install](docs/install.md) — Prebuilt binaries, package managers, and build from source
- [Quickstart](docs/quickstart.md) — Step-by-step first session.
- [Policy](docs/policy.md) — Full policy schema and examples.
- [Credentials](docs/credentials.md) — How Orca protects API keys, tokens, and secrets.
- [Replay](docs/replay.md) — Session review, verification, and reporting.
- [Commands](docs/commands.md) — CLI reference.
- [Plugin security model](docs/integrations/plugin-security-model.md)
- [Plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)
- [Migration from Aegis to Orca](docs/migration-aegis-to-orca.md)

---

## Development

```bash
zig build
zig build test
./zig-out/bin/orca --help
./zig-out/bin/orca redteam --ci
```
