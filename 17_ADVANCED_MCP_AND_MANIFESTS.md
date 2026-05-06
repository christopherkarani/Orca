# Phase 17 — Advanced MCP and Server Manifests

## Objective

Extend MCP support beyond the initial stdio proxy by adding server manifests, resource/prompt/sampling controls, and compatibility groundwork for remote/HTTP MCP transports.

At the end of this phase, Aegis should provide a credible v1.0 MCP firewall surface.

---

## Scope

Implement:

- MCP server manifest format.
- Manifest loading and validation.
- MCP resource mediation.
- MCP prompt mediation.
- MCP sampling controls.
- Tool argument redaction improvements.
- Compatibility hooks for streamable HTTP/remote MCP.
- `aegis mcp trust`.
- `aegis mcp list`.
- `aegis mcp manifest`.
- Tests with fake MCP servers.

---

## Non-goals

Do not build a hosted MCP gateway.

Do not implement enterprise OAuth management.

If remote HTTP MCP is too large, implement a compatibility interface and minimal local test transport rather than overbuilding.

---

## Manifest Format

Example:

```yaml
version: 1
server:
  name: github
  transport: stdio
  command: github-mcp-server
  args: []
  expected_hash: null
  env:
    allow:
      - GITHUB_TOKEN

tools:
  search_issues:
    risk: low
    default: allow
  create_pull_request:
    risk: high
    default: ask
  delete_repository:
    risk: critical
    default: deny

resources:
  default: ask

prompts:
  default: ask

sampling:
  default: deny
```

---

## MCP Resource Controls

Mediate:

- `resources/list`
- `resources/read`

Policy examples:

```yaml
mcp:
  servers:
    docs:
      resources:
        allow:
          - "repo://docs/**"
        deny:
          - "file://~/.ssh/**"
```

---

## MCP Prompt Controls

Mediate:

- `prompts/list`
- `prompts/get`

Prompts can inject instructions into agents, so log and optionally require approval for prompt retrieval.

---

## Sampling Controls

Sampling lets an MCP server request a model call. Treat sampling as sensitive.

Default:

```yaml
mcp:
  sampling:
    default: deny
```

Support:

- deny
- ask
- allow for trusted server
- argument redaction
- audit events

---

## Remote/HTTP Compatibility

Implement a transport abstraction:

```text
stdio transport
http transport placeholder or minimal implementation
```

If implementing HTTP:

- Enforce max response sizes.
- Redact secrets in URLs/headers.
- Apply network policy.
- Log remote server identity.
- Do not persist tokens in logs.

If not fully implementing HTTP in this phase, create clear interfaces and docs.

---

## CLI

```bash
aegis mcp list
aegis mcp trust github --tool search_issues
aegis mcp manifest generate --command ./server
aegis mcp manifest check ./manifest.yaml
```

---

## Tests

Add tests for:

- Manifest parsing.
- Manifest validation.
- Tool default from manifest.
- Resource read allow/deny.
- Prompt get ask/deny.
- Sampling deny by default.
- Tool argument redaction.
- Unknown server behavior.
- Transport abstraction.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- MCP manifests load and influence policy.
- Resources/prompts/sampling are mediated.
- Sampling defaults to deny.
- `aegis mcp list` and `aegis mcp trust` work at a basic level.
- Remote/HTTP transport support is either implemented minimally or clearly stubbed with tests around the abstraction.
- Docs explain supported MCP features and limitations.

---

## Codex Execution Prompt

```text
Implement Phase 17: Advanced MCP and Server Manifests.

Add MCP server manifests, resource/prompt/sampling policy controls, improved argument redaction, mcp list/trust/manifest commands, and transport abstraction for remote/HTTP MCP compatibility. Do not build a hosted gateway.

Run:
- zig build
- zig build test
- manual smoke: aegis mcp manifest check
- manual smoke: fake server with resources/prompts/sampling

Provide a handoff with files changed, tests run, known limitations, and security notes.
```

---

## Handoff Notes for Next Phase

Agent presets will use MCP manifests and policy templates. Keep manifest paths and formats documented.


---

## Review Addendum — Advanced MCP Scope Control

Remote/HTTP MCP should be implemented only if it can be bounded and tested. Otherwise, provide a clean transport abstraction and keep v1.0 claims focused on stdio plus manifest/resource/prompt/sampling controls.

Sampling defaults to deny. Prompts and resources are untrusted and must be audited.


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
