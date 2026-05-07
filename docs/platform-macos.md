# macOS Platform Notes

macOS support is production-oriented for wrapper/proxy-mediated controls, not universal transparent sandboxing.

Aegis currently provides policy evaluation, environment filtering, command classification through wrappers/shims, staged writes for Aegis-mediated writes, protected path matching for common sensitive paths, stdio MCP proxy mediation, network decision heuristics, redaction, and audit/replay.

Transparent filesystem monitoring is not claimed. Transparent network enforcement is not claimed unless `aegis doctor` reports an active backend. macOS docs and demos must describe unsupported protections as limited or wrapper-only.

macOS sensitive path tests use synthetic `~/Library` and browser/profile paths. Tests must not read real user Keychain, browser, SSH, or cloud credential files.
