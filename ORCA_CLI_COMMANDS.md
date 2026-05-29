# Orca CLI Command Reference

> Generated from source at `src/cli/mod.zig`, `src/cli/help.zig`, `src/main.zig`, and individual command modules.
> Version: 1.1.5 (from `VERSION`)
> Product: **Orca** — Local runtime firewall for AI agents (Codex, Claude Code, OpenCode, OpenClaw, Hermes)

Orca ships **one** CLI binary:
- **`orca`** — The desktop/CI AI-agent runtime firewall (main product)

---

## `orca` — Top-Level Commands

Invocation: `orca <command> [options]`

| Command | Summary | Source File |
|---------|---------|-------------|
| `run` | Run a command under Orca | `src/cli/run.zig` |
| `init` | Create an Orca policy | `src/cli/init.zig` |
| `setup` | Guided post-install setup for agent host integrations | `src/cli/setup.zig` |
| `doctor` | Show platform capabilities | `src/cli/doctor.zig` |
| `policy` | Validate, explain, and apply policies | `src/cli/policy.zig` |
| `credentials` | Check Secretless credential brokers | `src/cli/credentials.zig` |
| `report` | Export a local safety report | `src/cli/report.zig` |
| `license` | Manage local offline licenses | `src/cli/license.zig` |
| `replay` | Replay an audit session | `src/cli/replay.zig` |
| `diff` | Show staged writes | `src/cli/diff.zig` |
| `apply` | Apply staged writes | `src/cli/apply.zig` |
| `discard` | Discard staged writes | `src/cli/discard.zig` |
| `mcp` | MCP proxy and inspection commands | `src/cli/mcp.zig` |
| `redteam` | Run red-team fixtures | `src/cli/redteam.zig` |
| `completions` | Generate shell completions | `src/cli/completions.zig` |
| `shim` | Internal PATH shim callback | `src/cli/shim.zig` |
| `version` | Print version | `src/cli/version.zig` |
| `plugin` | Plugin management and diagnostics | `src/cli/plugin.zig` |
| `decide` | Evaluate a policy decision for host plugins | `src/cli/decide.zig` |
| `hook` | Host-specific hook adapter | `src/cli/hook.zig` |
| `dashboard` | Start the local Orca dashboard | `src/cli/dashboard.zig` |
| `ci` | Run local CI readiness checks | `src/cli/ci.zig` |
| `demo` | Create safe local demo evidence | `src/cli/demo.zig` |
| `disable` | Disable Orca plugins from host agents | `src/cli/disable.zig` |
| `uninstall` | Uninstall Orca from this machine | `src/cli/uninstall.zig` |
| `help` | Show help | `src/cli/help.zig` |
| `env` | Print install environment for shell activation | `src/cli/mod.zig` |
| `--print-install-env` | Hidden flag (same as `env`) | `src/cli/mod.zig` |

### Exit Codes (`src/cli/exit_codes.zig`)

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `success` | OK |
| 1 | `general` | General error |
| 2 | `usage` | Usage error |
| 3 | `denial` | Action denied |
| 4 | `unsupported` | Unsupported feature |
| 5 | `child_failure` | Child process failed |
| 6 | `redteam_failure` | Red-team fixture failure |
| 7 | `ask` | Decision asks (non-interactive hosts read JSON) |
| 8 | `warn` | Decision warn/redact outcome |

---

## Command Details

### `orca run`

Run a command under Orca supervision — filters environment through policy, checks the command through Command Guard, writes audit artifacts, and mirrors the child exit code.

**Usage:** `orca run [options] -- <command> [args...]`

**Default mode:** `observe` (from `RunOptions.mode = .observe`)

**Flags:**
| Flag | Description |
|------|-------------|
| `--workspace <path>` | Workspace root directory |
| `--mode <mode>` | Policy mode: `observe`, `ask`, `strict`, or `ci` |
| `--ci` | Shorthand for `--mode ci` |
| `--policy <path>` | Path to policy file |
| `--session-name <name>` | Session name for audit trail |
| `--no-secrets` | Strip secrets from child environment |
| `--secretless` | Replace secrets with broker references |
| `--inherit-env` | Inherit current environment (must be allowed by policy) |
| `--no-network` | Disable all network access (`--network off`) |
| `--allow-network <domain>` | Allow specific network destination (repeatable) |
| `--network <mode>` | Network mode: `observe`, `ask`, `allowlist`, `open`, `off` |
| `--network-backend <backend>` | Backend: `decision-only` or `proxy` |
| `--require-backend <capability>` | Require sandbox capability (repeatable) |
| `--help`, `-h` | Show help |

**Default network backend:** `decision-only`
**Default child environment:** Secrets stripped in `strict`/`ci` modes

---

### `orca init`

Create an Orca policy file (`.orca/policy.yaml`) in the current directory.

**Usage:** `orca init [--preset <name>] [--mode <mode>] [--ci] [--force] [--quiet]`

**Default preset:** `generic-agent`

**Flags:**
| Flag | Description |
|------|-------------|
| `--preset <name>` | Policy preset name |
| `--mode <mode>` | Override the preset's mode: `strict`, `ask`, `observe`, `ci`, `trusted` |
| `--ci` | Shorthand for `--mode ci` |
| `--force` | Overwrite existing `.orca/policy.yaml` |
| `--quiet` | Suppress informational output |
| `--help`, `-h` | Show help |

**Available presets** (from `orca_policy.presets.AgentPreset`):
`generic-agent`, `claude-code`, `codex`, `cursor-agent`, `opencode`, `cline-roo`, `mcp-dev`, `github-actions`, `solo-dev`, `strict-local`, `team-ci`, `openclaw-hermes`, `trusted-local`

---

### `orca setup`

Guided post-install setup for agent host integrations. On interactive terminals, launches a selector. Use `--auto` for non-interactive/scripting mode.

**Usage:** `orca setup [--auto] [--preset <name>]`

**Default preset:** `generic-agent`

**Flags:**
| Flag | Description |
|------|-------------|
| `--auto` / `--yes` | Non-interactive automatic mode (for scripts/CI) |
| `--preset <name>` | Policy preset to use |

---

### `orca doctor`

Show platform capabilities — reports sandbox backend features, network policy engine status, and platform limitations honestly.

**Usage:** `orca doctor [--help]`

No persistent flags.

---

### `orca policy`

Validate, explain, and apply policy files.

**Usage:** `orca policy <subcommand> [...]`

**Subcommands:**
| Subcommand | Usage | Description |
|------------|-------|-------------|
| `check` | `orca policy check <policy-path>` | Validate a policy file |
| `explain` | `orca policy explain [--policy <path>] <kind> <target> [--method <METHOD>]` | Explain a policy decision |
| `packs` | `orca policy packs` | List available policy packs |
| `apply-pack` | `orca policy apply-pack <name> [--force]` | Apply a policy pack |

**Available packs:** `solo-dev`, `strict-local`, `team-ci`, `openclaw-hermes`

**Explanation kinds:** `file.read`, `file.write`, `env`, `command`, `network`, `mcp`

---

### `orca credentials`

Check Secretless credential broker configuration.

**Usage:** `orca credentials check [credential-ref]`

**Supported brokers:** `local-dummy`, `env-file-dev`, `1password-cli`, `macos-keychain`, `infisical-agent-vault`

---

### `orca report`

Export a local safety report (Pro/Team license feature).

**Usage:** `orca report --session <id|last> --format <format>`

**Flags:**
| Flag | Description |
|------|-------------|
| `--session <id\|last>` | Session ID or `last` |
| `--format markdown\|json` | Output format |

---

### `orca license`

Manage local offline licenses.

**Usage:** `orca license <status|activate> [...]`

**Subcommands:**
| Subcommand | Usage | Description |
|------------|-------|-------------|
| `status` | `orca license status [--json]` | Show license status |
| `activate` | `orca license activate <key-or-file>` | Activate a license key |

**Development keys:** `dev-free`, `dev-pro`, `dev-team`

---

### `orca replay`

Replay an audit session — renders a timeline and can verify the event hash chain.

**Usage:** `orca replay [--session <id|last>] [--json] [--only denied] [--verify]`

**Flags:**
| Flag | Description |
|------|-------------|
| `--session <id\|last>` | Session ID (default: interactive selection) |
| `--json` | JSON output |
| `--only denied` | Show only denied actions |
| `--verify` | Verify hash chain |

---

### `orca diff`

Show unified diffs for Orca-mediated staged writes.

**Usage:** `orca diff [--session <id|last>] [--file <path>]`

---

### `orca apply`

Apply reviewed staged writes.

**Usage:** `orca apply [--session <id|last>] [--file <path>]`

---

### `orca discard`

Discard staged writes without changing workspace files.

**Usage:** `orca discard [--session <id|last>] [--file <path>]`

---

### `orca mcp`

MCP proxy and inspection commands.

**Usage:** `orca mcp <subcommand> [options]`

**Subcommands:**
| Subcommand | Usage | Description |
|------------|-------|-------------|
| `inspect` | `orca mcp inspect --command <server> [--name <name>] [--policy <path>]` | Inspect an MCP server |
| `proxy` | `orca mcp proxy --command <server> [options]` | Start an MCP proxy |
| `list` | `orca mcp list` | List configured MCP servers |
| `trust` | `orca mcp trust <server> --tool <tool>` | Trust an MCP tool |
| `manifest check` | `orca mcp manifest check <manifest.yaml>` | Validate a manifest |
| `manifest generate` | `orca mcp manifest generate --command <cmd> \| --server <name>` | Generate a manifest |

**Proxy options:** `--name <name>`, `--policy <path>`, `--manifest <path>`, `--mode observe|ask|strict|ci`

---

### `orca redteam`

Run red-team test fixtures against Orca controls and report a scorecard.

**Usage:** `orca redteam [path] [--json] [--ci] [--fixture <id>]`

**Default fixture path:** `./fixtures`

**Flags:**
| Flag | Description |
|------|-------------|
| `--json` | Machine-readable JSON report |
| `--ci` | Non-interactive; exits non-zero if any required fixture fails |
| `--fixture <id>` | Run a specific fixture by ID |

---

### `orca completions`

Generate shell completion scripts.

**Usage:** `orca completions <bash|zsh|fish|powershell>`

Prints a completion script to stdout.

---

### `orca shim`

Internal callback used by session-local PATH shims.

**Usage:** `orca shim exec -- <command> [args...]`

Automatically removes the session shim directory from PATH before resolving the real binary.

---

### `orca version`

Print the current version.

**Usage:** `orca version [--json] [--help]`

**Flags:**
| Flag | Description |
|------|-------------|
| `--json` | JSON output (version, commit, target, build_date) |
| `--help`, `-h` | Show help |

---

### `orca plugin`

Plugin management and diagnostics for host agent integrations.

**Usage:** `orca plugin <subcommand> [options]`

**Subcommands:**
| Subcommand | Usage | Description |
|------------|-------|-------------|
| `doctor` | `orca plugin doctor [codex\|claude\|opencode\|openclaw\|hermes] [--json]` | Check plugin status |
| `manifest` | `orca plugin manifest [codex\|claude\|opencode\|openclaw\|hermes\|all] [--json]` | Show plugin manifests |
| `install` | `orca plugin install [<host>\|all] [--dry-run] [--path <path>] [--yes]` | Install a plugin |
| `mcp-server` | `orca plugin mcp-server [--help]` | MCP server stub |

**Supported hosts:** `codex`, `claude`, `opencode`, `openclaw`, `hermes`

**Default install behavior:** `--dry-run` is default (no changes without explicit opt-in)

---

### `orca decide`

Evaluate a policy decision for host plugin integration. Returns JSON result.

**Usage:** `orca decide <kind> --json <payload>|--stdin [--ci]`

**Decision kinds:** `command`, `file`, `prompt`, `tool`

**Flags:**
| Flag | Description |
|------|-------------|
| `--json <payload>` | Inline JSON payload |
| `--stdin` | Read JSON payload from stdin |
| `--ci` | Non-interactive mode (ask → block) |

---

### `orca hook`

Host-specific hook adapter — normalizes host-specific events to Orca policy decisions.

**Usage:** `orca hook <host> <event> [--ci]`

**Supported hosts:** `codex`, `claude`, `opencode`, `openclaw`, `hermes`

**Events per host:**

| Host | Events |
|------|--------|
| **codex** | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop` |
| **claude** | `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionEnd` |
| **opencode** | `session.created`, `tool.execute.before`, `tool.execute.after`, `permission.asked`, `permission.replied`, `file.edited`, `command.executed`, `session.updated`, `session.idle`, `session.error`, `shell.env` |
| **openclaw** | `session.start`, `tool.before`, `tool.after`, `permission.before`, `permission.after`, `session.end` |
| **hermes** | `on_session_start`, `pre_tool_call`, `post_tool_call`, `pre_llm_call`, `post_llm_call`, `subagent_stop`, `on_session_end` |

Reads JSON payload from stdin, emits host-valid JSON response to stdout.

---

### `orca dashboard`

Start the local web dashboard.

**Usage:** `orca dashboard [--host <ip>] [--port <n>]`

**Defaults:** `--host 127.0.0.1 --port 7742`

---

### `orca ci`

Run local CI readiness checks — validates policy, rejects dangerous defaults, runs a CI-safe redteam fixture.

**Usage:** `orca ci check [--format markdown|json] [--github-summary <path>]`

**Subcommand:** `check` (required)

**Flags:**
| Flag | Description |
|------|-------------|
| `--format markdown\|json` | Output format (default: text) |
| `--github-summary <path>` | Append to GitHub Actions step summary |

---

### `orca demo`

Create safe local demo evidence — generates a harmless session showing a destructive command being denied.

**Usage:** `orca demo blocked-action`

No optional flags.

---

### `orca disable`

Disable Orca plugins from host agents without removing the Orca binary or policy files.

**Usage:** `orca disable [codex|claude|opencode|openclaw|hermes|all] [--yes]`

**Default:** disables all hosts

**Flags:**
| Flag | Description |
|------|-------------|
| `--yes` | Skip confirmation prompt |

---

### `orca uninstall`

Completely remove Orca and its integrations from the machine.

**Usage:** `orca uninstall [--plugins-only] [--keep-config] [--yes]`

**Flags:**
| Flag | Description |
|------|-------------|
| `--plugins-only` | Only remove plugins; keep binary and config |
| `--keep-config` | Remove plugins and binary but keep `~/.config/orca/` |
| `--yes` | Skip confirmation prompt |

---

### `orca help`

Show top-level or command-specific help.

**Usage:** `orca help [command]`

---

### `orca env`

Print shell activation commands for installing Orca into PATH.

**Usage:** `orca env`

Prints platform-appropriate `export PATH=...` (Unix) or `set PATH=...` (Windows) lines. Detects the actual binary location via `selfExePath` for correct paths.

**Also available as hidden flag:** `orca --print-install-env`

---

