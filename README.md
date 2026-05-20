# Orca &nbsp;[![Version](https://img.shields.io/badge/version-1.1.1-blue)](https://github.com/christopherkarani/Orca/releases) [![License](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE) [![Zig](https://img.shields.io/badge/built%20with-Zig-orange)](https://ziglang.org) [![Build](https://img.shields.io/github/actions/workflow/status/christopherkarani/Orca/build.yml?branch=main&label=build)](https://github.com/christopherkarani/Orca/actions/workflows/build.yml)

**i got tired of my AI agent trying to delete my entire repo**

so i wrote Orca. it sits between you and your agent and says "nah" before bad stuff happens. that's it. that's the pitch.

it wraps Codex, Claude Code, OpenCode, whatever you're using. intercepts tool calls at the MCP protocol level. stops `rm -rf`, `.env` reads, sketchy network calls. local-only, no cloud bs.

```bash
# install (macOS/Linux)
brew tap christopherkarani/orca && brew install --formula orca

# or use the script
curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh

# or build from source (Zig 0.15.2)
zig build
```

---

## quick demo

```bash
# 1. check it's working
orca doctor

# 2. make a policy
orca init --preset generic-agent

# 3. watch it block something bad (safely)
orca demo blocked-action

# 4. see what it caught
orca replay --session last --only denied --verify
```

no agent needed for the demo. nothing gets deleted.

---

## before vs after

| without Orca | with Orca |
|---|---|
| sweating over every AI suggestion, scared of `rm -rf` | you delegate. Orca blocks the bad ones |
| no idea what the agent actually did | replay the full session—allowed, denied, asked |
| accidentally paste `.env` into agent context | secrets get redacted before the agent sees them |
| team has zero shared rules | commit `.orca/policy.yaml`, everyone gets the same guardrails |
| find out about damage after it happened | see the block in real time, before anything happens |

---

## how people actually use it

**1. solo dev with Claude Code or Codex**
```bash
orca run -- claude
# code without hovering. Orca asks before sketchy actions.
```

**2. team lead who wants consistent rules**
```bash
# commit a policy to your repo
cat .orca/policy.yaml
# everyone who clones gets the same guardrails automatically
```

**3. CI running autonomous stuff**
```bash
orca run --ci -- codex --prompt "Refactor the auth module"
# non-interactive. no prompts. dangerous stuff gets blocked.
```

---

## what it actually does

AI agents can run shell commands, read files, make network requests. powerful. also risky. Orca gives you three things:

1. **block bad stuff before it happens**  
   stops `rm -rf`, `sudo`, `curl | sh`, reading `.env` and SSH keys.

2. **replay and audit sessions**  
   after the agent finishes, see exactly what it tried, what got allowed, what got denied. evidence is tamper-evident and stays local.

3. **share team guardrails**  
   commit `.orca/policy.yaml` to your repo. everyone gets the same rules.

---

## install

```bash
# macOS
brew tap christopherkarani/orca
brew install --formula orca

# Linux (amd64 / arm64)
curl -fsSL https://raw.githubusercontent.com/christopherkarani/Orca/main/scripts/install.sh | sh
```

script installs to `~/.local/bin` and adds to PATH. open a new terminal or `source ~/.zshrc`.

**want to build from source?** see [docs/install.md](docs/install.md).

after installing:

```bash
orca doctor
```

### 1. make your first policy

```bash
orca init --preset generic-agent
```

creates `.orca/policy.yaml`:

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

- `mode: ask` — asks before risky stuff when interactive
- `mode: strict` — blocks more aggressively
- `mode: observe` — logs decisions, minimal blocking
- `mode: ci` — never prompts. `ask` becomes `block`. good for automation.

validate it:

```bash
orca policy check .orca/policy.yaml
```

### 2. run an agent with guardrails

```bash
orca run -- codex
orca run -- claude
orca run -- opencode
orca run -- openclaw
orca run -- hermes
```

Orca launches the agent as a child process, intercepts tool calls, enforces policy in real time.

### 3. review a session

after the agent exits:

```bash
# see everything that was denied
orca replay --session last --only denied --verify

# export a report (requires local Pro/Team license)
orca license activate dev-pro
orca report --session last --format markdown

# JSON output for automation
orca replay --session last --only denied --json
```

session artifacts live under `.orca/sessions/<session-id>/`.

---

## architecture

Orca isn't a shell wrapper. it launches your agent as a child process and intercepts traffic at the **MCP** layer:

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│   you       │ ──▶  │    Orca      │ ──▶  │   AI agent      │
└─────────────┘      └──────────────┘      └─────────────────┘
                            │                        │
                            │                      tool call
                            │                        ▼
                     ┌──────────────┐      ┌─────────────────┐
                     │  policy      │ ◀──  │  MCP stdio      │
                     │  engine      │      │  proxy          │
                     └──────────────┘      └─────────────────┘
                            │
                    allow / deny / ask
```

1. **MCP stdio proxy** — sits between agent and MCP server, parses JSON-RPC 2.0 messages. every `tools/call`, `resources/read`, `prompts/get`, `sampling/createMessage` gets evaluated against policy before forwarding.

2. **command guard** — tokenizes and classifies shell commands by risk. `rm -rf /` blocked. `git status` allowed.

3. **network egress guard** — parses destinations, runs exfiltration heuristics (paste sites, tunneling services, base64-like URL components, high-entropy DNS labels).

4. **filesystem staging** — writes get staged to `.orca/sessions/<id>/staging/` with diff review before apply.

5. **audit hash chain** — every event serialized deterministically, hashed, chained. replay detects tampering.

6. **honest sandbox backends** — Linux backend probes for Landlock, seccomp-bpf, cgroups v2, user namespaces. macOS/Windows use wrapper-mediated enforcement with clear capability reporting. `orca doctor` shows exactly what's active, partial, or unavailable on your OS. no "we secure everything" marketing bs.

strongest protection is the `orca run` wrapper. Orca controls the agent process directly. host plugins exist for deeper integration, but plugins are limited by each host's hook system. for max safety, always run through `orca run`.

---

## supported agents

| agent | one-liner |
|-------|-----------|
| **Codex** | `orca run -- codex` |
| **Claude Code** | `orca run -- claude` |
| **OpenCode** | `orca run -- opencode` |
| **OpenClaw** | `orca run -- openclaw` |
| **Hermes** | `orca run -- hermes` |

optional native plugins for deeper integration. see [docs/integrations/](docs/integrations/) per agent.

---

## secretless mode (optional)

don't want the agent seeing raw credentials?

```bash
orca run --secretless -- codex
```

Orca filters the child environment before launch. secret-like values get replaced with safe `orca-secret://...` references. raw values never touch policy, audit, or replay artifacts.

broker adapters for `env-file-dev`, `1password-cli`, `macos-keychain`. see [docs/install.md](docs/install.md).

---

## policy reference

policies live in `.orca/policy.yaml`:

| section | controls |
|---------|----------|
| `commands` | shell commands the agent can run |
| `files` | file read/write access |
| `network` | outbound HTTP/HTTPS requests |
| `credentials` | secret broker config |
| `services` | service-scoped network rules |

full ref: [docs/policy.md](docs/policy.md)

---

## security model

- **local-first** — policy decisions, audit logs, replay evidence stay on your machine
- **policy-driven** — you write the rules, Orca enforces them
- **tamper-evident** — session logs with hash-chain verification
- **secret redaction** — sensitive values redacted before persistence
- **fails closed** — network proxy fails, Orca kills the child process

Orca doesn't promise perfect sandboxing. it protects agents launched *through* Orca. agents started outside the wrapper aren't covered.

run `orca doctor` to check your platform capabilities.

---

## docs

- [install](docs/install.md) — binaries, package managers, source builds
- [quickstart](docs/quickstart.md) — first session walkthrough
- [policy](docs/policy.md) — full schema and examples
- [replay](docs/replay.md) — session review and verification
- [commands](docs/commands.md) — CLI reference
- [plugin security](docs/integrations/plugin-security-model.md)
- [plugin troubleshooting](docs/integrations/plugin-troubleshooting.md)
- [migration from Aegis](docs/migration-aegis-to-orca.md)

---

## dev

```bash
zig build
zig build test
./zig-out/bin/orca --help
./zig-out/bin/orca redteam --ci
```

runs the built-in redteam suite. 10 deterministic fixtures against actual controls.
