# Phase 19 — Installers and Release Pipeline

## Objective

Create the cross-platform build, packaging, signing, checksum, SBOM, and release pipeline for Aegis.

At the end of this phase, Aegis should be easy to install and release on macOS, Linux, and Windows.

---

## Scope

Implement:

- Cross-platform build targets.
- Release artifact naming.
- Checksums.
- Optional signing hooks.
- SBOM generation hook.
- Homebrew formula template.
- Scoop manifest template.
- Winget manifest template.
- npm wrapper package.
- Docker image for CI.
- Install scripts.
- GitHub release workflow or equivalent CI workflow.
- Release checklist.

---

## Non-goals

Do not build paid distribution.

Do not require a signing key to build locally.

Signing can be implemented as optional release-time configuration.

---

## Release Artifacts

Produce artifacts for:

```text
aegis-vX.Y.Z-darwin-amd64.tar.gz
aegis-vX.Y.Z-darwin-arm64.tar.gz
aegis-vX.Y.Z-linux-amd64.tar.gz
aegis-vX.Y.Z-linux-arm64.tar.gz
aegis-vX.Y.Z-windows-amd64.zip
checksums.txt
sbom.json
```

Use names consistent with the project conventions.

---

## Install Script

Create:

```text
scripts/install.sh
scripts/install.ps1
```

The scripts should:

- Detect OS/arch.
- Download matching artifact.
- Verify checksum where possible.
- Install binary to a user-selected or default path.
- Print next steps.

Do not make install scripts unsafe. Avoid `curl | sh` messaging in Aegis docs unless accompanied by checksum and manual alternatives.

---

## Package Templates

Create package metadata:

```text
packaging/homebrew/aegis.rb
packaging/scoop/aegis.json
packaging/winget/aegis.yaml
packaging/npm/package.json
packaging/docker/Dockerfile
```

The npm package can be a wrapper that downloads the Zig-built binary.

---

## CI Workflow

Create release workflow:

```text
.github/workflows/build.yml
.github/workflows/test.yml
.github/workflows/release.yml
```

If GitHub Actions is not desired, place equivalent templates in `ci/`.

Build matrix:

- Linux x64
- Linux arm64 if feasible
- macOS x64
- macOS arm64
- Windows x64

---

## Versioning

Use SemVer:

```text
0.x: schemas may change
1.x: stable CLI, policy schema, event schema
```

Add:

```bash
aegis version --json
```

Example:

```json
{
  "version": "1.0.0",
  "commit": "abc123",
  "target": "x86_64-linux",
  "build_date": "2026-05-05T12:00:00Z"
}
```

---

## Tests

Add tests/checks for:

- Build target configuration.
- Artifact naming.
- Version output.
- Package metadata validity where feasible.
- Install script shellcheck or equivalent if available.
- Docker build if feasible.
- Release workflow syntax if feasible.

---

## Acceptance Criteria

- `zig build` succeeds.
- `zig build test` succeeds.
- Cross-platform build commands are documented.
- Release workflow exists.
- Checksums are generated.
- Package templates exist.
- Install scripts exist.
- `aegis version --json` works.
- Release checklist exists in docs.

---

## Codex Execution Prompt

```text
Implement Phase 19: Installers and Release Pipeline.

Add cross-platform release configuration, artifact naming, checksums, optional signing hooks, SBOM hook, install scripts, Homebrew/Scoop/Winget/npm/Docker packaging templates, CI workflows, version metadata, and release checklist.

Run:
- zig build
- zig build test
- any available package metadata validation
- version command smoke tests

Provide a handoff with files changed, tests run, known limitations, and release notes.
```

---

## Handoff Notes for Next Phase

Security hardening will rely on repeatable CI and release workflows. Keep build scripts deterministic.


---

## Review Addendum — Release Integrity

Release artifacts must include checksums. Signing can be optional before v1.0 only if the release docs clearly state the status, but checksum generation is mandatory.

Install scripts must have manual verification alternatives and should not encourage unsafe blind execution without checksum guidance.


---

## Reviewed Codex Context Requirement

When executing this phase with a Codex coding agent, provide this phase file together with `CODEX_AGENT_CONTEXT.md` and `CANONICAL_IMPLEMENTATION_DECISIONS.md`. For architecture-sensitive work, also provide `ARCHITECTURE_CONTRACTS.md`, `SECURITY_INVARIANTS.md`, and `PRODUCTION_READINESS_GATES.md`. If this phase conflicts with `CANONICAL_IMPLEMENTATION_DECISIONS.md`, the canonical decisions win.

This phase is not complete until:

- all phase acceptance criteria pass;
- relevant production gates pass;
- security invariants are preserved;
- tests are added for new behavior;
- limitations are documented honestly;
- the phase handoff is written.
