# Policy

Policies are YAML files with `version: 1`.

## Locations And Load Order

Commands accept `--policy <path>`. Without it, Aegis discovers `.aegis/policy.yaml` from the workspace, then `$HOME/.config/aegis/policy.yaml`, then built-in defaults. If a discovered policy file exists but is invalid or unreadable, Aegis fails closed instead of silently falling through.

```sh
./zig-out/bin/aegis init --preset generic-agent
./zig-out/bin/aegis policy check .aegis/policy.yaml
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
      - "./.aegis/**"
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
mcp:
  default: deny
  allow:
    - "*.list_*"
    - "*.get_*"
  deny:
    - "*.delete_*"
    - "*.run_command"
audit:
  level: full
  redact_secrets: true
  tamper_evident: true
```

Explain decisions:

```sh
./zig-out/bin/aegis policy explain file.read ./.env
./zig-out/bin/aegis policy explain command git status
./zig-out/bin/aegis policy explain network https://example.invalid/path
./zig-out/bin/aegis policy explain mcp demo.list_files
```

## Invalid Policy Behavior

Missing versions, unknown keys, invalid modes, malformed rule shapes, oversized files, and unsafe patterns fail validation. Enforcing modes fail closed.

## CI Behavior

CI never prompts. `ask` decisions become `deny`.

## Common Workflows

- Start broad: `aegis init --preset generic-agent`.
- Strict local work: `--preset strict-local`.
- MCP development: `--preset mcp-dev`.
- CI: `--preset github-actions` and `aegis redteam --ci`.
