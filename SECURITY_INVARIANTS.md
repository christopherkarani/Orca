# Security Invariants for Aegis v1.0

These invariants apply to every phase. A phase is not complete if it violates any invariant.

## 1. No Secret Persistence

Aegis must not persist raw secrets in:

- `events.jsonl`;
- `summary.json`;
- `summary.md`;
- replay output;
- red-team reports;
- debug logs enabled by default;
- fixture outputs;
- crash messages;
- generated docs or examples.

Synthetic fake secrets used in tests must also be redacted, proving the redaction path works.

## 2. Redaction Before Persistence

Redaction must happen before writing persistent logs. It is not sufficient to redact only at display time.

## 3. Fail Closed for Enforcement

In enforcing modes (`strict`, `ci`, and any future enforcing mode):

- invalid policy fails closed;
- audit log unavailable fails closed unless the user explicitly uses an unsafe override;
- unsupported sandbox setup fails to documented fallback and prints capability warning;
- parser errors on untrusted MCP/policy inputs fail closed for that action.

## 4. CI Mode Is Non-interactive

CI mode must never prompt for input. Any `ask` decision becomes `deny` unless an explicit CI allow rule exists.

## 5. Deny Priority

Explicit deny beats allow unless a deliberately designed, tested, and documented override mechanism exists.

## 6. Honest Capability Reporting

Aegis must not claim a protection is active unless it is actually active.

Capability states should distinguish:

- active;
- partial;
- limited;
- observe-only;
- unavailable.

This is especially important for:

- transparent file enforcement;
- transparent network enforcement;
- process tree containment;
- macOS sandboxing;
- Windows sandboxing.

## 7. No Universal Sandbox Claims

Aegis v1.0 may be production-ready without perfect sandboxing on every OS. It must document exact protections and limitations.

Marketing/docs must say Aegis reduces blast radius and improves visibility. They must not say Aegis makes arbitrary malicious code safe.

## 8. Bounded Untrusted Input

All parsers for untrusted input must enforce limits:

- policy file size;
- JSON/YAML nesting depth;
- MCP message size;
- MCP schema depth;
- MCP tool count;
- command length;
- URL length;
- log event size;
- fixture file size.

## 9. Deterministic Audit Integrity

Audit hash-chain verification must detect:

- modified events;
- removed events;
- reordered events;
- changed summary hash;
- invalid previous hash.

## 10. No Real Secrets or Real LLMs in Tests

Tests and demos must not require:

- real API keys;
- real SSH keys;
- real cloud credentials;
- real LLM calls;
- external webhook services;
- external network services.

Red-team fixtures should use fake agents and synthetic secrets.

## 11. Approval Must Be Explicit

Interactive approvals must show:

- action being requested;
- risk reason;
- matched policy/default;
- choices;
- scope of approval.

Session-level approvals must be logged.

## 12. Staged Writes Must Preserve Reviewability

When write staging is active:

- original content must be preserved or hash-recorded;
- diff must be available before apply;
- apply must verify expected original state where feasible;
- discard must remove staged content;
- staging metadata must not hide path escapes.

## 13. MCP Tool Calls Are Untrusted

MCP tools, prompts, resources, sampling requests, and tool metadata are untrusted by default.

Aegis must treat these as policy-controlled actions, not as trusted configuration.

## 14. Child Processes Are Untrusted

The agent process and subprocesses are untrusted. Any enforcement implemented only through shell wrappers must be documented as wrapper-level, not OS-level.

## 15. Security Errors Must Be Specific

Security-sensitive errors should preserve reason and context without leaking secrets.

Bad:

```text
failed
```

Good:

```text
Denied file read: path matches files.read.deny rule "~/.ssh/**".
```
