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

## Dashboard UI (`orca-dashboard-ui`)

Local operator UI exported as static assets under `orca-dashboard-ui/dist` and
served by the Zig `orca dashboard` command. These Node packages are **build-time
only** for the UI export; they are not linked into `orca` or `orca-daemon`.

| Package | Role | Notes |
|---|---|---|
| `next` ^15.1 | Static export / React app framework | Builds machine-wide + workspace dashboard |
| `react` / `react-dom` ^19 | UI runtime | Used only in the exported static bundle |
| `tailwindcss` ^3.4 + `postcss` / `autoprefixer` | Styling | Build-time CSS pipeline |
| `typescript` ^5.7 | Typecheck | Dev/build only |
| `lucide-react` ^0.460 | Icons | Presentation only |
| `shiki` ^1.24 / `ansi-to-html` ^0.7 | Code/ANSI rendering | Presentation of command output |
| `clsx` / `tailwind-merge` / `class-variance-authority` | Class composition | Presentation only |
| `geist` ^1.3 | Font package | Presentation only |

- License: primarily MIT (Next/React ecosystem). Review upstream licenses on
  upgrade.
- Security boundary: the dashboard UI talks to the local Zig dashboard HTTP
  server (CSRF-gated actions, localhost-only by default). It does not evaluate
  policy or replace the daemon. Secrets must still be redacted before any
  host-visible text is written.
- Why not Zig-only assets: the machine-wide operator UI needs a component model
  and static export pipeline; the existing Zig dashboard server continues to own
  API, authz, and feed aggregation.
- Testing: `npm test` in `orca-dashboard-ui` (contract tests) and
  `scripts/install-layout-smoke-test.sh` markers for the shipped export.

## Full Zig shell engine (2026-07-21)

New dependency: none.

In-process Zig `shell_engine` uses only the Zig standard library for MVP structured matching. The former Rust `orca-rs` daemon/evaluator crate (including regex-automata and related crates) is removed from the product tree.
