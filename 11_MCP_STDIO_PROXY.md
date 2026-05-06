# Phase 11 — MCP Stdio Proxy

## Objective

Implement Aegis as a policy-enforcing stdio MCP proxy.

At the end of this phase, Aegis should be able to sit between an MCP client and a local stdio MCP server, inspect JSON-RPC messages, log tools, enforce tool-call policy, and block suspicious or disallowed tool calls.

---

## Scope

Implement:

- Stdio proxy process.
- JSON-RPC parser/writer.
- MCP initialize forwarding.
- `tools/list` inspection.
- `tools/call` policy enforcement.
- Tool metadata scanning.
- Tool-call approval.
- MCP audit events.
- `aegis mcp inspect`.
- `aegis mcp proxy`.
- Tests with fake MCP server/client fixtures.

---

## Non-goals

Do not implement remote HTTP MCP yet. That comes later.

Do not implement full OAuth/authorization flows yet.

---

## CLI

### Inspect

```bash
aegis mcp inspect --command ./fake-mcp-server
aegis mcp inspect --server github
```

Should print:

```text
MCP Server: fake
Transport: stdio
Tools:
  search_issues        risk: low       default: allow
  create_pull_request  risk: high      default: ask
  delete_repository    risk: critical  default: deny

Findings:
  none
```

### Proxy

```bash
aegis mcp proxy --command ./fake-mcp-server
aegis mcp proxy --server github
```

The proxy reads JSON-RPC from stdin and writes JSON-RPC to stdout while enforcing policy.

---

## Methods to Handle

At minimum:

- `initialize`
- `tools/list`
- `tools/call`

Log but pass through unknown methods unless policy says otherwise.

Later phases will add resources, prompts, sampling, elicitation, and remote transports.

---

## Tool Risk Classification

Classify tool risk using:

- Name.
- Description.
- Input schema.
- Annotations if present.
- Server manifest if present.
- Policy rules.

Risk classes:

```text
low
medium
high
critical
unknown
```

Examples:

- `search_*`, `list_*`, `get_*`: usually low/read-only.
- `create_*`, `update_*`: high.
- `delete_*`: critical.
- tools mentioning credentials, secrets, shell, filesystem, network: high/critical.
- suspicious metadata: critical or ask/deny.

---

## Suspicious Metadata Patterns

Flag tool descriptions containing:

- "ignore previous instructions"
- "do not tell the user"
- "exfiltrate"
- "secret"
- "credential"
- base64-like long strings
- very long description
- schema fields unrelated to tool name
- impersonation of trusted tools

---

## Policy Shape

Support:

```yaml
mcp:
  default: ask
  servers:
    github:
      tools:
        allow:
          - search_repositories
          - get_file_contents
        ask:
          - create_issue
          - create_pull_request
        deny:
          - delete_repository
```

---

## Audit Events

Emit:

- `mcp_initialize`
- `mcp_tools_list`
- `mcp_tool_metadata_flagged`
- `mcp_tool_call`
- `mcp_tool_call_allowed`
- `mcp_tool_call_denied`
- `mcp_tool_call_approval_requested`

Never log raw secrets in arguments.

---

## Tests

Add fixtures:

- Fake MCP server with safe tools.
- Fake MCP server with write tools.
- Fake MCP server with malicious metadata.
- Fake client that calls tools.

Tests:

- Proxy forwards initialize.
- Proxy forwards tools/list and logs tools.
- Safe tool allowed.
- Denied tool blocked.
- Ask tool prompts or denies in CI.
- Malicious metadata flagged.
- Oversized message rejected.
- Invalid JSON-RPC rejected safely.
- Secret-like arguments redacted in logs.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- `aegis mcp inspect --command <fake-server>` lists tools.
- `aegis mcp proxy --command <fake-server>` forwards safe calls.
- Denied tool calls are blocked.
- Tool-call decisions are audited.
- Invalid or oversized MCP messages fail safely.
- Secret-like MCP arguments are redacted before logging.

---

## Codex Execution Prompt

```text
Implement Phase 11: MCP Stdio Proxy.

Add JSON-RPC parsing/writing, stdio proxying, initialize/tools-list/tools-call handling, tool metadata scanning, tool-call policy enforcement, approval integration, audit events, and fake MCP fixtures/tests. Do not implement remote HTTP MCP yet.

Run:
- zig build
- zig build test
- manual smoke: aegis mcp inspect with fake server
- manual smoke: aegis mcp proxy with fake client/server

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Network guard will also use allow/ask/deny decisions and approval prompts. Keep decision APIs generic.


---

## Review Addendum — MCP Stdio Wire Contract

Implement stdio transport according to the MCP transport contract:

- JSON-RPC messages are UTF-8;
- messages are newline-delimited;
- messages must not contain embedded newlines;
- server stderr is logs only and must not be parsed as MCP messages;
- server stdout must contain only valid MCP messages;
- Aegis must enforce maximum line/message size.

The proxy must not print human logs to stdout while proxying; human/debug logs must go to stderr or audit files.


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
