# Dependency Notes

## Phase 02

New dependency: none.

Aegis currently uses only the Zig standard library. Future dependencies must document:

- name and version/source;
- license;
- why Zig stdlib or local code is insufficient;
- whether the dependency parses untrusted input;
- whether it is used in security-critical code;
- how it is tested.
