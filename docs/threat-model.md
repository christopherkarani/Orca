# Threat Model

## Protects

Aegis protects Aegis-mediated local agent sessions by filtering environment variables, classifying commands, staging writes, mediating filesystem and network decisions through policy, proxying stdio MCP traffic, redacting synthetic/secret-like values before persistence, and writing tamper-evident audit logs.

## Does Not Protect

Aegis is not a perfect sandbox. It does not guarantee transparent interception of every file, process, or network action on every platform. Code that runs outside Aegis wrappers, shims, staged-write APIs, or the MCP proxy is outside the current enforcement path.

## Trust Boundaries

- Agent subprocesses and child tools are untrusted.
- MCP tools, prompts, resources, sampling requests, descriptions, and schemas are untrusted.
- Policy, fixture, and audit files are untrusted input and must be bounded.
- Audit logs are tamper-evident, not tamper-proof, unless externally anchored.

## Fail-Closed Rules

Strict and CI modes deny invalid or ambiguous security decisions where Aegis has an enforcement path. CI mode never prompts. Deny rules beat allow rules.
