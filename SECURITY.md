# Security Policy

## Supported Versions

Aegis is pre-release. No version is currently supported for production security use.

## Reporting a Vulnerability

Report suspected vulnerabilities privately to the project owner. Do not include real credentials, API keys, tokens, private keys, or customer data in reports.

## Current Phase Limitations

Phase 02 does not implement security enforcement. It creates the buildable scaffold and minimal CLI only. Later phases must preserve these invariants:

- no raw secret persistence;
- redaction before persistent logging;
- fail-closed behavior for enforcement modes;
- non-interactive CI behavior;
- honest capability reporting.
