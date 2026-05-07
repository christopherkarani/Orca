# Phase 19 Installers and Release Pipeline Plan

## Assumptions

- Phase 19 is limited to build, package, install, workflow, checksum, SBOM hook, signing hook, release checklist, and version metadata work.
- Release artifacts should package the built `aegis` binary plus runtime-supporting docs, policies, completions generation support, and preset files where applicable.
- Signing is optional and hook-based in this phase; local builds and normal CI must not require signing secrets.
- SBOM generation can be a deterministic metadata hook/template if no external SBOM tool is available locally.
- Install scripts may support GitHub release downloads by default but must also support local artifact/checksum paths for verification and testing.
- `aegis version --json` should be valid JSON with nullable or dev-safe metadata when CI does not inject commit/build date.

## Research Check

- [x] Read Phase 19 and required canonical, architecture, security, and production gate docs.
- [x] Review Aegis memory and lessons for phase boundaries, pinned Zig version, release integrity, and no false security claims.
- [x] Inspect current build, CLI version routing, docs, scripts, packaging, and GitHub workflow surfaces.
- [x] Validate assumptions against implementation after tests are in place: artifact names, checksum paths, metadata injection, package placeholders, CI command coverage, and no secret-looking template values.

## Checklist

- [x] Add focused tests/checks for `aegis version --json`, release artifact naming, release/package files, install script checksum paths, Dockerfile content, workflow command coverage, release checklist, and secret-pattern hygiene.
- [x] Implement version metadata injection in `build.zig` and CLI output for plain and JSON version commands.
- [x] Add release artifact naming/build helper logic and scripts for build, checksum generation, SBOM hook, and optional signing.
- [x] Add safe macOS/Linux and Windows install scripts with OS/arch detection, checksum verification, safe install defaults, clear failure modes, and no telemetry/secrets behavior.
- [x] Add package templates for Homebrew, Scoop, Winget, npm wrapper/downloader, and Docker CI image with clear placeholders and no credentials.
- [x] Add GitHub Actions build, test, and release workflow templates that run `zig build`, `zig build test`, red-team CI where feasible, preset validation where feasible, release packaging, checksums, optional signing, and optional SBOM.
- [x] Add release checklist/docs covering artifact names, manual checksum verification, signing/SBOM status, and honest limitations.
- [x] Run required verification: `zig build`, `zig build test`, `./zig-out/bin/aegis redteam --ci`, `./zig-out/bin/aegis version`, and `./zig-out/bin/aegis version --json`.
- [x] Run manual Phase 19 checks: script executability, unsupported OS/arch safe failures, placeholder fields, workflow commands, artifact naming consistency, checksum generation, and secret-pattern scan.
- [x] Document review results, known limitations, signing/SBOM status, security notes, and acceptance criteria status.

## Review

- Implemented build metadata injection with `-Dversion`, `-Dcommit`, and `-Dbuild-date`; local defaults keep builds working without CI metadata.
- Implemented `aegis version --json`; plain `aegis version` remains supported and prints `aegis 0.19.0-dev`.
- Added release artifact naming helpers and Zig tests for all Phase 19 artifact names.
- Added Phase 19 tests that package templates, installers, workflows, Dockerfile, release checklist, checksum paths, and secret-pattern hygiene are present.
- Added macOS/Linux and Windows install scripts with OS/arch detection, local or release artifact support, checksum verification before extraction/install, safe default install locations, no telemetry, and clear unsupported OS/arch failures.
- Added release helper scripts for cross-target archive generation, checksum generation, SBOM hook output, and optional signing command hooks.
- Added Homebrew, Scoop, Winget, npm wrapper/downloader, and Docker CI image templates with placeholder versions/checksums/license values where release automation must fill them.
- Added GitHub Actions `build.yml`, `test.yml`, and `release.yml` templates for build, tests, red-team CI, preset validation, release artifacts, checksums, optional signing, and SBOM hook output.
- Added `docs/release/checklist.md` with artifact names, required checks, manual checksum verification, signing status, SBOM status, and security notes.
- Final verification: `zig build --summary all` passed.
- Final verification: `zig build test --summary all` passed with 206/212 tests passed and 6 skipped.
- Final verification: `zig build check-windows --summary all` passed.
- Final verification: `./zig-out/bin/aegis redteam --ci` passed 10/10 fixtures.
- Final verification: `./zig-out/bin/aegis version` printed `aegis 0.19.0-dev`.
- Final verification: `./zig-out/bin/aegis version --json` emitted valid JSON with `commit` and `build_date` as null for local builds.
- Release smoke: `AEGIS_VERSION=0.19.0-dev AEGIS_DIST_DIR=dist-phase19-smoke ./scripts/build-release.sh` produced all five required archives plus `checksums.txt` and `sbom.json`.
- Release smoke: `shasum -a 256 -c dist-phase19-smoke/checksums.txt` verified all generated archives.
- Install smoke: `AEGIS_ARTIFACT_DIR=dist-phase19-smoke ./scripts/install.sh` installed the verified darwin-arm64 artifact into a temp directory and the installed binary returned JSON version metadata.
- Install safety smoke: unsupported OS override failed clearly with `aegis install: unsupported operating system: Plan9`.
- Package syntax checks passed for shell scripts, Homebrew Ruby, Scoop/npm JSON, and npm wrapper JavaScript.
- PowerShell parser check was not run because `pwsh` is not installed locally.
- Secret-pattern scan over packaging, scripts, workflows, release docs, audit logs, and replay output found no obvious raw credential patterns.
- Known limitation: signing is hook-only and not proof of signed/notarized artifacts until a release environment provides and runs a signing command.
- Known limitation: SBOM generation is hook/placeholder output unless release automation swaps in CycloneDX/SPDX tooling.
- Known limitation: npm package is a wrapper/downloader template and intentionally does not download binaries while checksum placeholders remain.
