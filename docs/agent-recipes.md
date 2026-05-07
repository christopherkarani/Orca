# Agent Recipes

## Generic Coding Agent

```bash
aegis init --preset generic-agent
aegis policy check .aegis/policy.yaml
aegis run -- ./scripts/agent-task.sh
```

Use this for a first local run. Writes are staged and common risky commands stay behind policy decisions.

## MCP Development

```bash
aegis init --preset mcp-dev
aegis mcp manifest generate --command ./server -- --stdio > .aegis/mcp/server.yaml
aegis mcp manifest check .aegis/mcp/server.yaml
aegis mcp proxy --manifest .aegis/mcp/server.yaml --command ./server -- --stdio
```

Manifest trust is bound at proxy launch. A manifest does not make a server trusted by name alone.

## CI Mode

```bash
aegis init --preset github-actions
aegis run --mode ci -- ./scripts/agent-task.sh
```

CI mode never prompts. Ask decisions are denied unless the policy contains an explicit allow.

## Strict Local Mode

```bash
aegis init --preset strict-local
aegis policy check .aegis/policy.yaml
```

Use this for untrusted tasks. Add narrow allows only after reviewing policy explanations.

## Trusted Local Mode

```bash
aegis init --preset trusted-local
aegis policy check .aegis/policy.yaml
```

Use this only in repositories you already trust. It is still redacted and staged, but it is intentionally less restrictive.

## Red-Team Run

```bash
aegis redteam --ci
```

Fixtures are deterministic and local. They do not call real LLMs or require real credentials.

## Staged Write Review

```bash
aegis run -- ./scripts/agent-task.sh
aegis diff --session last
aegis apply --session last
```

Staging applies only to Aegis-mediated writes. Aegis does not claim universal transparent filesystem interception on every platform.
