# Build, Test, Package, CI

## Build System

Use `build.zig` as the source of build truth:

- Define modules with explicit imports.
- Keep generated options in one `b.addOptions()` surface.
- Install artifacts through `b.installArtifact`.
- Add named steps for tests, docs checks, release checks, benches, and smoke commands.
- Use `b.standardTargetOptions` and `b.standardOptimizeOption` unless the repo has a stricter pattern.
- Run `zig build --help` after adding options so the interface is visible.
- Keep compile-time build options stable and centralized; scattered `@import("build_options")` values become release metadata bugs.
- Do not hide target-specific skips in `build.zig`; report skipped/unsupported explicitly in tests or docs.

When adding files required by package consumers, update `build.zig.zon.paths`. Missing files can pass local tests and fail package fetch/archive consumers.

## Package Manager

- Keep `build.zig.zon.minimum_zig_version` aligned with CI and docs.
- Update dependency hashes through `zig fetch` or the compiler's exact suggested hash.
- Treat fingerprint changes as trust-sensitive. Do not guess.
- Package paths are the release surface. Keep docs, schemas, fixtures, scripts, generated checked-in artifacts, and runtime resources listed when consumers need them.
- Check archive/package content before release:

```bash
zig fetch --debug-hash .
git archive --format=tar HEAD | tar -tf - | sort | sed -n '1,120p'
```

## Tests

Prefer this order:

```bash
zig test path/to/focused_test.zig
zig build test --summary all
zig build
```

Use direct binary invocations for CLI exit-code checks:

```bash
zig build
./zig-out/bin/<tool> <args>
echo $?
```

Avoid spawned-child tests that inherit noisy stdout/stderr under Zig's test protocol when the repo has seen hangs. Use ignored stdio for test-only children and keep real CLI paths inherited.

## Test Design

- Put tiny unit tests near the code when they exercise pure behavior.
- Put integration tests in named test files when they need fixtures, package resources, or CLI surfaces.
- Add regression tests for every review finding before fixing it.
- For parsers, include valid minimum input, valid maximum/boundary input, unknown fields, duplicate fields, malformed/truncated input, and oversize input.
- For CLIs, test stdout/stderr shape only as tightly as scripts require; test exit codes exactly.
- For safety/security logic, assert negative cases first and verify deny beats allow.
- Avoid tests that rely on wall-clock sleeps; prefer deterministic time injection.

## Fuzz, Bench, Smoke

- Use fuzzing or generated malformed fixtures for parsers and protocols.
- In Zig 0.16, review the fuzzer and unit-test timeout release notes before changing fuzz/test harness behavior.
- Keep benchmarks separate from correctness tests.
- Run performance tests in ReleaseFast or the repo's benchmark mode, but validate same-output behavior first.
- Smoke installed artifacts from outside the repo root when packaging/resource lookup matters.

## CI

- Pin the Zig version in CI.
- Build and test every supported target that the project claims.
- Treat cross-compilation success as compile proof, not runtime proof.
- Keep secrets out of test fixtures and logs.
- Fail CI when generated docs/schemas/release files drift if they are part of the committed contract.
- Verify dirty-tree hygiene: new modules/tests/resources must be visible in `git diff` or tracked before claiming clean-checkout readiness.
