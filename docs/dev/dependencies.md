# Dependency Notes

## Phase 02

New dependency: none.

At Phase 02, Orca used only the Zig standard library. New dependencies must document:

- name and version/source;
- license;
- why Zig stdlib or local code is insufficient;
- whether the dependency parses untrusted input;
- whether it is used in security-critical code;
- how it is tested.

## Phase 24

New dependency: none.

Orca Core facade, schema registry, and experimental ABI skeleton use only the Zig standard library and existing in-repo modules. No new parser, security-critical dependency, external network dependency, or hardware dependency was added.

## CLI TUI

Dependency: `libvaxis` 0.6.0, pinned to commit
`ca781b3c01f44a92e5331652823b5a9ce445be96` and Zig package
hash `vaxis-0.6.0-BWNV_Gz5CQBTx7g34RYMPTL-bJhsFCU3ECHQ-CZlBVsn` in
`build.zig.zon`.

- License: MIT.
- Purpose: portable terminal capability detection, raw input, and interactive
  widgets for Orca's guided CLI flows. The standard library does not provide a
  terminal UI/event abstraction.
- Security boundary: libvaxis renders terminal UI and parses terminal input. It
  does not evaluate policy, authorize commands, or parse Orca machine APIs.
  Linear and machine output remain implemented in Orca and do not depend on it.
- Pin verification: Zig verifies the package hash before use. Generated package
  contents live in ignored `zig-pkg/`; no dependency source is vendored.
- Transitive audit: libvaxis pins `zigimg` at
  `d695acd97c02e57bb151e8f659d1280f5cd6ca70` and lazy `uucode` at
  `2826a37a4562284fdacd8fa029d49509cc9bffcd`. Neither is used in Orca policy or
  daemon trust decisions. `uucode` is also declared in Orca's root manifest and
  wired as libvaxis's external Unicode module because Zig does not fetch the
  upstream lazy dependency reliably from a clean local package cache. Updates
  require reviewing the upstream manifests,
  licenses, and Zig package hashes, then running the CLI test and release gates.
- Release dry-run size accounting: `scripts/release-dry-run.sh` now extracts the
  built host archive and reports `orca` plus `orca-daemon` byte sizes. The first
  Phase 8 dry-run on darwin-arm64 established `orca` at 2,828,488 bytes and
  `orca-daemon` at 19,752,816 bytes; no hard threshold is enforced.
