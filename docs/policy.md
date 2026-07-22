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
- `yolo`: **YOLO + seatbelt** — first-class mode for autonomous agent work. Uses the same severity matrix as `ask` (low continues; medium/high may prompt; not refuse-all). The agent continues under sandbox (Seatbelt/Landlock when session-attached) plus the hard fence. Prefer `yolo` over treating “ask on everything” as the hero path. Built-in preset: `orca policy check --preset yolo` / `mode: yolo` in YAML.
- `strict`: deny unknown or risky actions unless allowed. When a shell **permit-list is configured** for Strict evaluation (`commands.allow` / host permit), commands **off** that list are **refused** (deny, never ask-spam); reason includes `strict: not on allowlist`. On-list does **not** auto-allow high/medium pack hits — the severity matrix still applies after the refuse gate. With an **empty / unconfigured** permit list, Strict keeps the existing severity matrix only (not refuse-all-off-list).
- `ci`: non-interactive strict behavior; ask becomes deny.
- `redteam`: strict fixture mode for deterministic tests (strict-like permit refuse when a list is configured).
- `trusted`: observe-like mode for local trusted workflows.

### Hard fence (unsoftenable)

Critical severity and always-on catastrophe classes (for example `rm -rf /`) are always **denied**. **YOLO**, sticky trust, and Strict permit lists **cannot** unlock the hard fence.

### Sticky trust

After an interactive **ask** that the user allows, Orca can record sticky trust so a later identical command (or effect class) skips re-ask:

| Scope | Behavior |
|-------|----------|
| **once** | One subsequent allow for that command fingerprint, then consumed |
| **session** | Allow that fingerprint until process/session end |
| **effect-class** | Allow a semantic effect-class id for the session |

Sticky state is **in-memory for the session** only (no on-disk sticky in this phase). Critical / hard-fence denies are **never** recorded as sticky allows.

### Shell evaluation order

For shell mediation (hook / run / shim), decisions follow this order:

1. empty command / evaluator error → deny (fail closed)
2. engine allow → allow
3. **critical hard fence** → deny (ignore sticky, mode, and permit)
4. sticky match (once / session / effect-class) → allow
5. **strict refuse** off permit-list when mode is strict-like and a list is configured → deny
6. mode × severity matrix → allow | ask | warn | block

Foundation Models / on-device policy stewards are **not** a shipping claim for Phase 2 YOLO/Strict/sticky — residual upgrade paths (if any) are later work, not required for this layer.

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
tables + host tags + optional local residual). No cloud LLM classification.

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
3. **User effect packs (high/medium)** — workspace and user-config YAML packs
   add exact names, tokens, and structural key-sets. Matchers use
   `pack.<id>.*`. Packs are **classification-only**; they never grant allow
   past `effects.deny`.
4. **Local residual classifier (low, opt-in)** — when `effects.classifier` is
   `local` (or `local-embed`, same engine in v1), tools that A–C leave
   under-classified may pick up low-confidence hits via pure-Zig
   prototype/token similarity on the tool **name**, argument **keys**, and
   bounded short alphanumeric string **value tokens** (secrets filtered;
   not chat history, not a cloud model). Matchers use `classifier.local.*`.
   **Off by default.** Raise-only: residual hits may increase restriction
   (ask/deny) but never alone flip a surface deny into allow. In `strict` /
   `ci` / `redteam`, if the classifier is enabled but unavailable, residual
   tools **fail closed** (`effects.classifier unavailable`).
5. **Network host tags** — when `effects:` is active, destinations such as
   `api.twitter.com` map to `comms.publish` (matcher `network_tag.…`) and
   merge with network surface rules on **both** `policy explain network` and
   the runtime proxy (`orca run` / `network_eval.evaluate`).
6. **Shell bypass (Zig command path)** — patterns such as `open mailto:…`
   (including `open -a Mail mailto:…`), multi-URL `curl` to tagged hosts, and
   command-position matching (including wrappers such as `sudo`/`env`/`xargs`)
   map to `comms.message` / `comms.publish` (matcher `shell_bypass.…`) on Zig
   `command` / `orca policy explain command` evaluation.

Example residual opt-in (block-style lists):

```yaml
version: 1
mode: strict
effects:
  default: ask
  deny:
    - comms.message
    - comms.publish
  classifier: local
```

Surfaces covered:

- Host generic tools (PreToolUse non-shell/file) **with tool_input/args** for
  structural matches (and user effect packs when present)
- `orca decide tool --json '{"name":"…","tool_input":{…}}'` (same arg shapes)
- `orca policy explain tool <name> --args '{…}'` for demos
- `orca tools classify <name> [--args '{…}'] [--policy <path>]` for discovery
- MCP `tools/call` via the proxy (name + `arguments` object)
- `orca mcp inspect` shows inferred effects per listed tool
- Network connect evaluation when effects are configured (explain **and**
  proxy-mediated runtime)
- Zig command evaluation (`orca policy explain command`, `command_exec`)

### User effect packs

Extend the built-in catalog without listing every tool name in policy YAML:

| Priority | Path |
|----------|------|
| Lowest | Built-in Zig catalog / structural / network / shell |
| Mid | `$XDG_CONFIG_HOME/orca/effect-packs/*.yaml` or `~/.config/orca/effect-packs/` |
| Highest | Workspace `.orca/effect-packs/*.yaml` |

Example (see also `examples/effect-packs/demo.yaml`):

```yaml
version: 1
id: acme-comms
description: optional
names:
  send_acme_ping: comms.message
tokens:
  acmechat: comms.message
structural:
  - effect: comms.message
    keys: [acme_to, acme_body]
```

Rules:

- `version: 1` only; `id` must match `[a-z0-9_-]{1,64}`
- Effect ids must be known (`comms.message`, …)
- Unknown keys, bad ids, or oversized files **fail closed** (clear error; no silent ignore of that file)
- Missing pack directories are fine
- Within a directory, packs load in **lexicographic filename order**; later files win on exact-name conflicts (workspace still outranks user config)
- Exact names match full normalized tool names and the last `__`/`/` segment (e.g. pack `send_acme_ping` matches `mcp__acme__send_acme_ping`)
- Tokens reuse catalog matching: short tokens (≤3 chars) require a whole `_`-separated segment
- Structural `keys` lists are capped (max 16 keys per rule)
- **Decisions still require policy `effects:`** — e.g. `effects.deny: [comms.message]` blocks pack-mapped tools

List loaded packs: `orca tools packs`.

### Discovery

```sh
./zig-out/bin/orca tools classify send_email
./zig-out/bin/orca tools classify notify --args '{"to":"a@b.com","body":"hi"}'
./zig-out/bin/orca tools classify send_acme_ping --policy .orca/policy.yaml
./zig-out/bin/orca mcp inspect --name demo --policy .orca/policy.yaml --command python3 -- fixtures/mcp/fake_server.py
```

Inspect and classify print effect ids, confidence, and matcher labels only —
never raw email/body/token values.

### Residual gaps

- **Host shell PreToolUse** is owned by the in-process Zig **`shell_engine`**
  (oracle pack parity; default enablement matches Rust `core.*` + `system.disk`).
  `ORCA_SHELL_EVAL=rust` is rejected — there is no supported dual-stack Evaluate
  backend. Network effect tags still catch many
  `curl`-style bypasses when the network path is evaluated (including the proxy).
- Structural classification is top-level + one nested object level of keys
  (interesting keys preferred against padding); deeper nesting or stringified
  JSON args are not fully covered.
- Host file PreToolUse uses `files.write` / `files.read` (not effect IDs on
  that specialized route). Denying `shell.exec` / `fs.write` as effects only
  applies when the call is evaluated as a **tool name**.
- Browser/computer-use UI actions remain out of scope.
- Residual classifier v1 is **local prototype/token similarity**, not neural
  embeddings or a remote LLM. `local-embed` is an alias for `local`. Features
  are tool name tokens, arg keys, and bounded short alphanumeric string value
  tokens (secret-looking values filtered). It only runs on under-classified
  tools and only raises restriction.

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

- Start broad: `orca init --preset generic-agent` (ask-matrix baseline; edit allowlists as needed).
- YOLO + seatbelt local autonomy: set `mode: yolo` (or `orca policy check --preset yolo`) so the agent continues under sandbox + hard fence without treating every action as an ask prompt.
- Strict local work: `--preset strict-local` (`mode: strict` with a sample `commands.allow` permit list — off-list refuse when the host wires that list into shell evaluation).
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
