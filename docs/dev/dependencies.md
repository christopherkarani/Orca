# Dependency Notes

## Phase 02

New dependency: none.

Orca currently uses only the Zig standard library. Future dependencies must document:

- name and version/source;
- license;
- why Zig stdlib or local code is insufficient;
- whether the dependency parses untrusted input;
- whether it is used in security-critical code;
- how it is tested.

## Phase 24

New dependency: none.

Orca Core facade, schema registry, and experimental ABI skeleton use only the Zig standard library and existing in-repo modules. No new parser, security-critical dependency, external network dependency, or hardware dependency was added.
