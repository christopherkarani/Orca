# Phase 07 — Policy Engine

## Objective

Implement the policy parser, validator, matcher, and explanation system.

At the end of this phase, Aegis should load policy files, validate them, evaluate simple decisions, explain why actions were allowed/denied/asked, and expose `aegis policy check` and `aegis policy explain`.

---

## Scope

Implement:

- Policy file discovery.
- Built-in policy templates.
- YAML or JSON policy parsing.
- Policy validation.
- Policy modes.
- Rule matching for paths, env vars, commands, network domains, and MCP tools.
- Decision priority.
- Policy explanations.
- Policy-loaded audit events.
- `aegis policy check`.
- `aegis policy explain`.

---

## Non-goals

Do not implement actual enforcement yet except where easy to wire through existing run behavior. This phase builds the decision engine.

---

## Policy Load Order

1. CLI `--policy <path>`.
2. `.aegis/policy.yaml` in workspace.
3. User config `~/.config/aegis/policy.yaml`.
4. Built-in preset.

---

## Policy Modes

| Mode | Behavior |
|---|---|
| `observe` | Log decisions but do not block |
| `ask` | Ask for risky actions |
| `strict` | Default deny sensitive actions |
| `ci` | Non-interactive, fail closed |
| `redteam` | Hostile fixture mode |
| `trusted` | Lower-friction local development |

---

## Minimum Policy Schema

Support this shape initially:

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
    - "AWS_*"

files:
  read:
    allow:
      - "./**"
    deny:
      - "./.env"
      - "./.env.*"
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
  default: ask
  allow:
    - "git status"
    - "git diff *"
  deny:
    - "rm -rf *"
    - "curl * | sh"
    - "sudo *"

network:
  default: deny
  allow:
    - "api.github.com"
    - "registry.npmjs.org"

mcp:
  default: ask
  servers: {}

audit:
  level: full
  redact_secrets: true
  tamper_evident: true
```

If YAML support requires a dependency, evaluate whether a small dependency is acceptable. JSON can be supported first if needed, but `.yaml` should be supported by v1.0.

---

## Decision Priority

Default order:

1. Explicit deny.
2. Explicit allow.
3. Explicit ask.
4. Risk heuristic.
5. Mode default.

Deny wins unless a future explicit override mechanism is implemented.

---

## Rule Matching

Implement:

- Exact string.
- Glob-style wildcard.
- Path-ish glob.
- Domain wildcard such as `*.github.com`.
- Command pattern string matching.
- MCP selector matching: `server.tool`.

Regex can be deferred unless easy.

---

## Policy Explanation

Command:

```bash
aegis policy explain file.read ~/.ssh/id_ed25519
```

Output:

```text
Decision: deny
Reason: matched files.read.deny rule "~/.ssh/**"
Rule: files.read.deny[2]
Mode: strict
```

Support explain types:

```bash
aegis policy explain file.read <path>
aegis policy explain file.write <path>
aegis policy explain env <name>
aegis policy explain command <command string>
aegis policy explain network <domain>
aegis policy explain mcp <server.tool>
```

---

## Tests

Add tests for:

- Valid policy parsing.
- Invalid policy errors.
- Policy discovery order.
- Mode parsing.
- Path allow/deny.
- Env allow/deny.
- Command allow/deny.
- Network domain allow/deny.
- MCP tool allow/deny.
- Explanation includes matched rule.
- Deny priority over allow.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis policy check .aegis/policy.yaml` works.
- Invalid policies produce clear errors.
- `aegis policy explain file.read ~/.ssh/id_ed25519` returns deny with rule.
- `aegis run --policy <path> -- echo hello` emits a policy-loaded event.
- Built-in policies exist for `observe`, `ask`, `strict`, and `ci`.

---

## Codex Execution Prompt

```text
Implement Phase 07: Policy Engine.

Add policy discovery, parsing, validation, decision matching, explanations, built-in presets, and CLI commands `aegis policy check` and `aegis policy explain`. Wire policy loading into `aegis run` and emit a policy_loaded audit event. Do not overbuild enforcement yet.

Run:
- zig build
- zig build test
- manual smoke: aegis policy check policies/strict.yaml
- manual smoke: aegis policy explain file.read ~/.ssh/id_ed25519

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Environment filtering will use `policy.env`. Make sure policy APIs are easy to call from the supervisor.


---

## Review Addendum — Policy API Contract

Policy evaluation should expose one common API used by env, files, commands, network, and MCP. Do not create separate incompatible evaluators.

YAML support is expected by v1.0. If Phase 07 chooses JSON-first to avoid dependency risk, it must document the gap and make Phase 22 block v1.0 until YAML policies work or the docs explicitly standardize on JSON. Preferred outcome: support YAML and JSON with a documented dependency or small parser.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
