# Linux Platform Notes

Linux is the target for the strongest eventual OS-level backend. Current capability status must be checked with `aegis doctor`.

Active cross-platform controls include policy evaluation, environment filtering, command classification through Aegis wrappers/shims, staged writes for Aegis-mediated writes, stdio MCP proxy mediation, network decision heuristics, redaction, and audit/replay.

Transparent filesystem and network enforcement are only active when the backend reports them as active. If Linux kernel features are missing or not wired, Aegis must report limited, observe-only, wrapper-only, or unavailable.

Known limitation: path-based controls cannot prove original provenance of a hardlink with an innocuous name. Use OS permissions and repository hygiene for hardlink-sensitive environments.
