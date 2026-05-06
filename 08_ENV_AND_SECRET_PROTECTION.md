# Phase 08 — Environment and Secret Protection

## Objective

Prevent agents from receiving secrets by default and redact secret-like values from persistent logs.

At the end of this phase, `aegis run` should launch child processes with a filtered environment according to policy, block common secret environment variables, and redact secret-like values before writing audit logs.

---

## Scope

Implement:

- Environment filtering.
- Env allowlist and deny patterns.
- Default no-secrets behavior.
- Secret name detection.
- Secret value detection.
- Redaction fingerprints.
- Redaction events.
- `--no-secrets`.
- `--inherit-env` if appropriate.
- Tests with synthetic secrets.

---

## Non-goals

Do not implement OS keychain integration, 1Password/Bitwarden integration, or brokered secret actions yet.

---

## Default Behavior

In `strict` and `ci` modes:

- Do not inherit the full environment.
- Allow only safe variables:
  - `PATH`
  - `HOME` where needed
  - `USER` or equivalent where needed
  - `LANG`
  - `LC_*`
  - `TERM`
  - platform-required variables
- Deny secret-like names.

In `observe` mode:

- Environment may be inherited, but secret-like values should still be redacted from logs.

In `trusted` mode:

- Environment can be inherited if policy allows.

---

## Secret-like Environment Names

Deny or redact names matching:

- `*TOKEN*`
- `*SECRET*`
- `*PASSWORD*`
- `*PASSWD*`
- `*PRIVATE*`
- `*KEY*`
- `AWS_*`
- `GITHUB_TOKEN`
- `GH_TOKEN`
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GOOGLE_API_KEY`
- `GOOGLE_APPLICATION_CREDENTIALS`
- `AZURE_*`
- `NPM_TOKEN`
- `PYPI_TOKEN`
- `SSH_AUTH_SOCK`

Policy should be able to override safely, but default should be conservative.

---

## Secret Value Detection

Detect and redact:

- PEM private key headers.
- AWS access key patterns.
- GitHub token-like values.
- OpenAI/Anthropic-style API key values.
- JWT-like strings.
- High-entropy long strings.
- Cloud credential JSON snippets.
- SSH private key blocks.

Do not rely only on entropy. Use a combination of name-based and value-based detection.

---

## Redaction Format

Use stable fingerprints:

```text
[REDACTED:env:GITHUB_TOKEN:sha256:8f1c2a9b]
[REDACTED:secret:aws_access_key:sha256:31a93f0c]
```

The fingerprint lets users correlate repeated redactions without exposing the secret.

---

## Audit Events

Emit events such as:

```json
{
  "type": "secret_redacted",
  "target": {
    "kind": "env",
    "name": "GITHUB_TOKEN"
  },
  "decision": {
    "result": "redact",
    "reason": "environment variable name matches secret pattern"
  }
}
```

Do not log the raw value.

---

## CLI Behavior

Add flags:

```bash
aegis run --no-secrets -- <command>
aegis run --inherit-env -- <command>
```

`--inherit-env` should be unavailable or warning-heavy in `strict`/`ci` unless policy allows it.

---

## Tests

Add tests for:

- Env allowlist.
- Env deny pattern.
- Known secret env names.
- Secret value redaction.
- Redaction fingerprints are stable.
- Audit logs do not contain synthetic secret values.
- Child process receives allowed env vars.
- Child process does not receive denied env vars.

Synthetic test secrets should be clearly fake.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis run --no-secrets -- <env-print-helper>` does not expose fake secret env vars.
- Audit logs redact synthetic secret values.
- Redaction emits events without leaking values.
- Policy `env.allow` and `env.deny_patterns` are respected.
- Default strict policy strips common secret variables.

---

## Codex Execution Prompt

```text
Implement Phase 08: Environment and Secret Protection.

Add policy-driven environment filtering to `aegis run`, default no-secrets behavior, secret-name detection, secret-value redaction, stable redaction fingerprints, and audit events. Add tests using synthetic secrets and verify audit logs do not leak them.

Run:
- zig build
- zig build test
- manual smoke with a fake env var such as FAKE_GITHUB_TOKEN

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Filesystem protection will use the same redaction and policy explanation conventions. Keep redaction APIs reusable.


---

## Review Addendum — Redaction Must Be Reusable

Secret detection and redaction should be implemented as a reusable module called by audit, MCP, network, command, and red-team code. Do not make it environment-only.

Tests must assert that the exact fake secret string is absent from all persisted session files, not merely absent from terminal output.


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
