# Phase 12 — Network Egress Guard

## Objective

Implement network egress policy, observation, allowlists, and basic exfiltration heuristics.

At the end of this phase, Aegis should support network policy decisions, log outbound destinations where observable, block or prompt for unknown destinations in strict mode where technically feasible, and detect obvious exfiltration patterns.

---

## Scope

Implement:

- Network policy model.
- Domain/IP allow/deny/ask matching.
- Exfiltration heuristics.
- Network decision audit events.
- Proxy-aware network guard.
- Environment variables for HTTP proxy integration where useful.
- CLI flags:
  - `--no-network`
  - `--allow-network <domain>`
  - `--network observe|ask|allowlist|open|off`
- Tests for domain matching and exfil heuristics.

---

## Important Reality Check

Transparent network enforcement is platform-specific. Do not claim universal enforcement until platform backends support it.

This phase should implement:

1. A complete network policy decision engine.
2. Proxy-mediated enforcement for tools that honor proxy settings.
3. Integration points for platform backends.
4. Honest capability reporting.

---

## Network Modes

| Mode | Behavior |
|---|---|
| `off` | No network allowed |
| `ask` | Prompt per unknown destination |
| `allowlist` | Allow listed destinations only |
| `observe` | Log but do not block |
| `open` | Allow all, log all |

---

## Policy Example

```yaml
network:
  mode: allowlist
  allow:
    - "api.github.com"
    - "*.github.com"
    - "registry.npmjs.org"
    - "pypi.org"
  ask:
    - "*.githubusercontent.com"
  deny:
    - "pastebin.com"
    - "*.ngrok.io"
    - "*.requestbin.net"
  detect_exfiltration:
    dns: true
    long_query_strings: true
    secret_patterns: true
```

---

## Destination Matching

Support:

- Exact domain.
- Wildcard domain.
- Direct IP.
- CIDR ranges if feasible.
- Private network ranges.
- Localhost.
- Link-local metadata endpoints.
- Ports if feasible.

Default strict behavior:

- Block direct IPs unless allowed.
- Block private network ranges unless allowed.
- Block localhost access unless allowed.
- Block cloud metadata IPs.

---

## Exfiltration Heuristics

Flag:

- Long query strings.
- Base64-like URL components.
- High-entropy DNS labels.
- Paste sites.
- Webhook/request-bin services.
- Tunneling services.
- Direct IP destinations.
- Secret-like substrings in URLs.
- Unusually long subdomains.
- Multiple failed attempts to different domains.

---

## Audit Events

Emit:

- `network_connect_attempt`
- `network_connect_allowed`
- `network_connect_denied`
- `network_exfiltration_suspected`

Include:

- destination host
- port if known
- protocol if known
- matched rule
- risk reason
- whether enforcement was direct, proxy-mediated, or observe-only

---

## CLI Behavior

Examples:

```bash
aegis run --no-network -- claude-code
aegis run --allow-network api.github.com -- codex
aegis run --network observe -- node agent.js
```

---

## Tests

Add tests for:

- Exact domain allow.
- Wildcard domain allow.
- Deny beats allow.
- Unknown domain in strict mode.
- Direct IP denied.
- Private IP denied.
- Long query flagged.
- Base64-like URL flagged.
- Secret-like URL redacted.
- Network events are logged.
- `--no-network` sets mode off.
- `--allow-network` adds temporary allow rule.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Network policy decisions are testable without real network.
- Proxy-mediated mode exists and is documented.
- CLI flags update network policy for a run.
- Network events are logged with redaction.
- `aegis doctor` reports current network enforcement capability honestly.
- Docs explain platform limitations.

---

## Codex Execution Prompt

```text
Implement Phase 12: Network Egress Guard.

Add network policy decisions, domain/IP matching, CLI flags, basic exfiltration heuristics, network audit events, proxy-mediated enforcement hooks, and honest capability reporting. Do not overclaim transparent enforcement.

Run:
- zig build
- zig build test
- manual smoke with network decision tests or a local fake request path

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

The red-team suite will test secret exfiltration through network-like fixtures. Make the network decision engine easy to call from fixtures.


---

## Review Addendum — Network Enforcement Levels

Network decisions must always record the enforcement mechanism:

- `os_enforced`;
- `proxy_enforced`;
- `shim_enforced`;
- `observed_only`;
- `not_available`.

A denied policy decision is not the same as a successfully enforced OS-level block. Logs and doctor output must distinguish them.


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
