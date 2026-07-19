# Policy

Policies are YAML files with `version: 1`.

## Locations And Load Order

Commands accept `--policy <path>`. Without it, Orca discovers `.orca/policy.yaml` from the workspace, then `$HOME/.config/orca/policy.yaml`, then built-in defaults. If a discovered policy file exists but is invalid or unreadable, Orca fails closed instead of silently falling through.

```sh
./zig-out/bin/orca init --preset generic-agent
./zig-out/bin/orca policy check .orca/policy.yaml

> **Quick-install note**: The generated policy is the conservative embedded variant (network `default: deny`, broad secret read denys, dual-path .git/.orca protection). It is designed to be edited after init. See the "What to expect" guidance in quickstart.md.
```

## Modes

- `observe`: log decisions without blocking supported actions.
- `ask`: prompt for risky actions when interactive.
- `strict`: deny unknown or risky actions unless allowed.
- `ci`: non-interactive strict behavior; ask becomes deny.
- `redteam`: strict fixture mode for deterministic tests.
- `trusted`: observe-like mode for local trusted workflows.

## Priority

Explicit deny beats allow. Ask is denied in CI unless an explicit allow rule applies.

## Examples

```yaml
version: 1
mode: strict
workspace:
  root: "."
  write_mode: staged
env:
  inherit: false
  allow:
    - PATH
    - HOME
    - LANG
    - TERM
  deny_patterns:
    - "*TOKEN*"
    - "*SECRET*"
    - "*KEY*"
files:
  read:
    allow:
      - "./**"
    deny:
      - "./.env"
      - "~/.ssh/**"
      - "~/.aws/**"
  write:
    allow:
      - "./**"
    deny:
      - "./.git/**"
      - "./.orca/**"
    mode: staged
commands:
  default: deny
  allow:
    - "git status"
    - "zig build *"
  deny:
    - "rm -rf *"
    - "curl * | sh"
    - "cat .env"
network:
  mode: allowlist
  default: deny
  allow:
    - "api.github.com"
  deny:
    - "pastebin.com"
    - "*.ngrok.io"
services:
  github:
    hosts:
      - "api.github.com"
    methods:
      - "GET"
      - "POST"
    paths:
      allow:
        - "/repos/*/issues"
        - "/repos/*/pulls"
      deny:
        - "/user/keys"
        - "/orgs/*/secrets/*"
    credentials:
      use: github_pat
    unmatched: deny
mcp:
  default: deny
  allow:
    - "*.list_*"
    - "*.get_*"
  deny:
    - "*.delete_*"
    - "*.run_command"
effects:
  # Optional. When present, tool calls are also classified into semantic effects
  # (comms.message, comms.publish, money.transfer, …) independent of exact tool names.
  default: allow
  deny:
    - comms.message
    - comms.publish
    - money.transfer
  ask:
    - unknown.external
audit:
  level: full
  redact_secrets: true
  tamper_evident: true
```

`audit.redact_secrets` may be omitted (it defaults to `true`) or explicitly set
to `true`. Setting it to `false` is rejected: persisted audit records and
exported replay data never permit raw secrets.

## Effects (semantic tool intent)

When the `effects:` section is present, Orca classifies mediated actions into
coarse **effect IDs** and evaluates them in addition to surface rules (`mcp`,
`commands`, `files`, `network`). Missing `effects:` keeps legacy behavior (no
effect evaluation). Classification is **deterministic** (catalog + structural
tables + host tags) — no LLM.

| Effect ID | Meaning |
|-----------|---------|
| `comms.message` | Email, SMS, iMessage, Slack/Discord/Telegram-style messaging |
| `comms.publish` | Public social posts (Twitter/X, LinkedIn, …) |
| `comms.calendar` | Calendar / invite side effects (reserved; limited catalog coverage) |
| `money.transfer` | Payments and transfers |
| `identity.auth` | Token/PAT/OAuth minting |
| `device.control` | Physical / IoT actuation |
| `code.mutate_remote` / `secrets.read` | Reserved for later phases (valid in YAML; limited emitters today) |
| `shell.exec` / `fs.read` / `fs.write` / `net.connect` | Tool-name surface IDs for shell/fs/net-shaped **tool names** |
| `unknown.external` | Unclassified outbound-looking tool names or arg shapes |

Patterns may be exact IDs or family wildcards (`comms.*`). **Any denied effect
denies**; deny beats allow. Equal severity keeps the **surface** result.
Structural hits only **raise** restriction — they never alone flip a surface
deny into allow. Explicit MCP allow does not override an effect deny.

### How classification works

1. **Tool name catalog (high confidence)** — exact names and domain tokens
   (`send_email` → `comms.message`, `post_twitter` → `comms.publish`).
2. **Structural args (medium)** — renamed tools such as `notify` / `helper`
   still match when argument **keys** form known sets (e.g. `{to, body}`) or
   string **values** look like email/phone/known messaging-API URLs. Reasons
   include matcher ids such as `structural.comms.message.keys:to+body` (keys
   only — never raw secret values).
3. **Network host tags** — when `effects:` is active, destinations such as
   `api.twitter.com` map to `comms.publish` (matcher `network_tag.…`) and
   merge with network surface rules.
4. **Shell bypass (Zig command path)** — patterns such as `open mailto:…`
   map to `comms.message` (matcher `shell_bypass.…`) on Zig `command` /
   `orca policy explain command` evaluation. Optional: `curl` to a tagged host.

Surfaces covered:

- Host generic tools (`orca decide tool`, PreToolUse non-shell/file) **with
  tool_input/args** for structural matches
- MCP `tools/call` via the proxy (name + `arguments` object)
- Network connect evaluation when effects are configured
- Zig command evaluation (`orca policy explain command`, `command_exec`)

### Residual gaps

- **Host shell PreToolUse** still primarily uses the **Rust daemon** and
  `commands` packs. Phase B shell effect patterns apply on the **Zig** command
  evaluation path; full Rust-pack parity is not claimed. Network effect tags
  still catch many `curl`-style bypasses when the network path is evaluated.
- Host file PreToolUse uses `files.write` / `files.read` (not effect IDs on
  that specialized route). Denying `shell.exec` / `fs.write` as effects only
  applies when the call is evaluated as a **tool name**.
- Browser/computer-use UI actions and user-authored effect packs are later
  phases.

When `effects:` is present, `effects.default` applies to **tool**
classification hits that match no allow/deny/ask pattern and to **tools with
zero hits** (unclassified names). Network/shell effect merge only runs when a
tag or bypass pattern hits — untagged hosts are not denied solely by
`effects.default`.

Preset: `no-external-comms` (`orca init --preset no-external-comms`).

Explain decisions:

```sh
./zig-out/bin/orca policy explain file.read ./.env
./zig-out/bin/orca policy explain command "open 'mailto:x@y.com'"
./zig-out/bin/orca policy explain network https://example.invalid/path
./zig-out/bin/orca policy explain network https://api.twitter.com/2/tweets
./zig-out/bin/orca policy explain network https://api.github.com/repos/acme/app/issues --method POST
./zig-out/bin/orca policy explain mcp demo.list_files
./zig-out/bin/orca policy explain tool send_email
./zig-out/bin/orca policy explain tool notify --args '{"to":"a@b.com","body":"hi"}'
```

## Invalid Policy Behavior

Missing versions, unknown keys, invalid modes, malformed rule shapes, oversized files, and unsafe patterns fail validation. Enforcing modes fail closed.

## CI Behavior

CI never prompts. `ask` decisions become `deny`.

## Common Workflows

- Start broad: `orca init --preset generic-agent`.
- Strict local work: `--preset strict-local`.
- MCP development: `--preset mcp-dev`.
- CI: `--preset github-actions` and `orca redteam --ci`.

## Secretless Runtime

`orca run --secretless -- <agent-command>` removes raw secret-like environment values from the child process and replaces policy-visible secret env entries with `orca-secret://...` broker references. Today those rewrites always use the **local-dummy** broker (reference-only; does not resolve raw values). Orca does not store raw secrets and does not inject raw secrets into the child environment or into model-provider HTTP. Coding agents that need env API keys will not authenticate under secretless; **do not default** agent launches to `--secretless` until a product path supplies usable credentials. See [credentials.md](credentials.md) § Secretless Mode and [agent-recipes.md](agent-recipes.md).

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
    macos:
      type: macos-keychain
  refs:
    github_pat:
      broker: onepassword
      ref: "op://Engineering/GitHub PAT/token"
```

Supported broker kinds are `local-dummy`, `env-file-dev`, `1password-cli`, `macos-keychain`, and `infisical-agent-vault`. `env-file-dev` is local-development only. `1password-cli` and `macos-keychain` resolve through their CLIs at check/runtime boundaries with bounded execution time and redacted timeout/login/missing-ref error classes. Infisical / Agent Vault is currently a status/config boundary only.

Use:

```bash
orca credentials check
orca credentials check github_pat
```

When `credentials.refs` are declared, `services.*.credentials.use` must point to one of those refs.
