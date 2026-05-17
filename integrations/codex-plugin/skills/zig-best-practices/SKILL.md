---
name: zig-best-practices
description: Production Zig engineering guidance for coding agents. Use when writing, reviewing, debugging, refactoring, testing, packaging, or migrating Zig code, especially around allocator ownership, error handling, std library version drift, build.zig/build.zig.zon, cross-compilation, C interop, performance, safety, security, and Zig 0.15/0.16-era patterns as of 2026-05-13.
---

# Zig Best Practices

## Operating Mode

Use this skill to make Zig changes with production discipline, not as a style essay. Start by proving the active toolchain and project contract, then load only the reference files needed for the task.

First checks:

```bash
zig version
zig env
test -f build.zig.zon && sed -n '1,80p' build.zig.zon
zig build --help
```

If `zig` is unavailable, inspect `build.zig.zon`, CI files, docs, and lockfiles; report that compile verification is blocked instead of guessing.

As of 2026-05-13, upstream Zig has `0.16.0` as the latest tagged release and `0.17.0-dev` builds available, but many active projects remain pinned to `0.15.x`. Prefer the repo pin over generic advice. Treat `std` APIs as version-sensitive.

## Reference Map

Load the minimum needed references:

- [version-migration.md](references/version-migration.md): version checks, 0.15 to 0.16 drift, official docs to refresh.
- [language-patterns.md](references/language-patterns.md): style, declarations, generics/comptime, type design, data layout.
- [memory-lifetime.md](references/memory-lifetime.md): allocators, ownership, slices, cleanup, tests for leaks.
- [errors-apis.md](references/errors-apis.md): errors, optionals, API surfaces, public contracts.
- [build-test-package.md](references/build-test-package.md): `build.zig`, `build.zig.zon`, package hashes, tests, fuzz/bench lanes, CI.
- [concurrency-io.md](references/concurrency-io.md): threads, process/env handling, 0.16 I/O interfaces, filesystem and networking.
- [interop-targets.md](references/interop-targets.md): C ABI, `translate-c`, cross-compilation, libc, OS support.
- [performance-security.md](references/performance-security.md): safety modes, profiling, bounds, parsers, crypto, secure coding.
- [agent-review-workflows.md](references/agent-review-workflows.md): task-specific checklists for implementation, review, migration, debugging, and release work.

## Default Workflow

1. Establish version and boundaries.
   Read `build.zig.zon.minimum_zig_version`, CI install steps, and existing code style. If the repo targets 0.15.2, do not silently migrate to 0.16 APIs.

2. Write or identify a failing proof.
   For bug fixes, add a focused test that fails first. For build/package changes, add a `build.zig` step, script check, or fixture test that exercises the exact failure.

3. Design the ownership contract.
   Before editing Zig code, decide which values are borrowed, owned, transferred, allocator-backed, stack-backed, or comptime-only. Document only non-obvious transfer points.

4. Implement narrowly.
   Match local style. Prefer explicit error unions and allocator parameters over hidden globals. Avoid speculative abstractions.

5. Verify in layers.
   Run focused tests first, then `zig build test --summary all` or the repo's documented equivalent. For CLI behavior, run the built binary directly when exit-code accuracy matters.

6. Review for version drift.
   Re-check APIs that changed in 0.16: I/O, process args/env, current path, managed/unmanaged containers, `std.mem` find/cut naming, `@cImport`, test timeouts, local package overrides.

7. Run the right review lens.
   Load `agent-review-workflows.md` before broad reviews, migrations, security-sensitive patches, or release work so findings are concrete and verification-oriented.

## Production Checklist

- Memory: every allocation has one clear owner, one clear free path, and tests use `std.testing.allocator` or an equivalent leak-detecting allocator.
- Errors: no swallowed errors, no broad `anyerror` in public APIs unless the boundary is intentionally opaque, no unchecked `catch unreachable` on runtime input.
- Lifetimes: no returned slices into stack buffers, freed env buffers, temporary parser buffers, or arena memory that dies before the caller.
- Safety: parse external data as hostile, reject unknown schema keys when security meaning matters, avoid unchecked casts, keep ReleaseFast assumptions explicit.
- Build: dependencies and generated artifacts are represented in `build.zig.zon.paths`; package fingerprints are updated from Zig's exact suggested value.
- Testing: cover success, malformed input, ownership cleanup, target/platform edges, and exit codes. Use `--summary all` where supported.
- Cross-platform: verify at least compile-time target behavior for supported platforms; do not report runtime support from compile success alone.
- Public APIs: expose small composable types, keep ownership in names/docs/tests, avoid leaking internal `std` version churn into stable surfaces.
- Performance: measure before optimizing, keep safety checks on while debugging, benchmark ReleaseFast separately, and preserve same-output proof.

## Nuance Traps

- `comptime` is not a substitute for simpler runtime code; use it when it improves type safety or removes real duplication.
- `packed`/`extern`/pointer casts are layout contracts, not performance decorations.
- Arena allocation simplifies cleanup but can hide unbounded memory growth in long-running services.
- Cross-compilation proves codegen and linking, not runtime behavior, filesystem semantics, sandbox behavior, or OS integration.
- ReleaseFast benchmark wins are irrelevant unless tests prove identical behavior and safety checks are not masking invalid assumptions.
- Zig version advice ages quickly. Refresh from official docs for stdlib details before making broad claims.

## Source Refresh

When the answer depends on current Zig behavior, refresh from primary sources before making claims:

- `https://ziglang.org/download/`
- `https://ziglang.org/documentation/<version>/`
- `https://ziglang.org/documentation/<version>/std/`
- `https://ziglang.org/download/<version>/release-notes.html`
- `https://ziglang.org/learn/build-system/`
