# Agent Review Workflows

## Choose The Lens

Load this file when the user asks for a review, broad audit, implementation plan, migration, production hardening, or debugging pass.

- Code review: findings first, grounded in files/lines, with severity and concrete failure mode.
- Implementation: TDD first, minimal patch, focused verification, then broader build/test.
- Migration: compiler-driven batches, no behavior changes unless required, version notes updated together.
- Debugging: reproduce, isolate, fix root cause, add regression, verify the original symptom.
- Release/package: prove clean checkout, package contents, installed resource lookup, checksums/hashes, and direct binary smokes.

## Code Review Checklist

- Allocation and lifetime: dangling slices, missing deinit, borrowed map keys, arena escape, allocator mismatch.
- Error paths: swallowed errors, `catch unreachable`, optional traps, lost `OutOfMemory`, cleanup after partial construction.
- Input handling: bounds, unknown fields, duplicate fields, enum conversion, integer overflow, path traversal, symlink escape.
- Version drift: stdlib API mismatch with `minimum_zig_version`, CI pin, docs, release notes.
- Build graph: missing module imports, untracked new files, package paths, stale generated artifacts.
- Cross-platform: target gates, libc assumptions, path/env/process differences, runtime support overclaims.
- Security: secret logging, capability overclaiming, policy defaults, unsafe fallbacks, shell-string construction.
- Tests: regression exists, negative cases covered, exit codes exact, package/outside-cwd smoke included when relevant.

## Implementation Checklist

1. Read the local contract: `build.zig.zon`, `build.zig`, CI, nearby tests, and project notes.
2. Write or identify a failing proof.
3. Decide ownership and error contracts before editing.
4. Patch the smallest code surface that fixes the proof.
5. Run focused verification.
6. Run the repo-standard build/test lane.
7. Check `git diff --check` and untracked files.

## Migration Checklist

1. Capture current baseline with the old compiler.
2. Update version metadata and CI in one batch.
3. Fix build-system breakage first.
4. Fix language/std changes in themed batches.
5. Keep public behavior stable; add compatibility shims where needed.
6. Run direct binary smokes and package/archive checks.
7. Document unsupported targets or blocked verification honestly.

## Debugging Checklist

- Prefer the smallest reproduction over broad rewriting.
- Check whether the failing binary is stale after cross-target or release builds.
- Separate parser/schema bugs from fixture/doc drift.
- Inspect generated and runtime artifacts as untrusted input.
- When behavior differs outside repo cwd, test resource lookup from a temp directory.
- After fixing, run the exact command that failed before and one nearby negative case.

## Done Criteria

- The diff contains only relevant source/docs/tests/scripts/resources.
- Every new file needed by build/package/review is tracked or visible in the diff.
- The exact failure is covered by a test or command.
- Version-sensitive claims cite the local pin or official docs.
- Remaining blocked verification is named with the missing tool, command, or environment.
