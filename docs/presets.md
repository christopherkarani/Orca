# Policy Presets

Presets live under `policies/presets/` and are plain YAML with comments. They are designed as editable starting points, not immutable security profiles.

Create a policy:

```bash
aegis init --preset generic-agent
aegis policy check .aegis/policy.yaml
```

Available presets:

- `generic-agent`: conservative local coding-agent baseline.
- `claude-code`: generic/experimental local coding-agent assumptions for Claude Code-style use.
- `codex`: generic/experimental local coding-agent assumptions for Codex-style use.
- `cursor-agent`: generic/experimental local editor-agent assumptions.
- `opencode`: generic/experimental local coding-agent assumptions.
- `cline-roo`: generic/experimental local editor/MCP-agent assumptions.
- `mcp-dev`: stdio MCP development baseline with conservative tool defaults.
- `github-actions`: non-interactive CI baseline.
- `strict-local`: strict local baseline with denied unknown commands/network.
- `trusted-local`: more permissive local baseline for trusted repositories; secret redaction and deny rules remain active.

All presets preserve:

- deny-priority semantics;
- secret redaction before persistence;
- staged writes for Aegis-mediated writes;
- no real secrets in policy text;
- no external service dependency for policy validation.

Agent-specific presets are marked generic/experimental when Aegis cannot verify proprietary agent internals. Binary detection in `aegis doctor` only reports presence in PATH; it does not prove an agent is configured safely.
