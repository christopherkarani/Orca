---
name: zig-memory-safety
description: Zig memory-safety review and implementation workflow for coding agents. Use when writing, reviewing, debugging, or refactoring Zig code that touches allocators, ownership, lifetimes, slices, pointers, arenas, unsafe casts, parser buffers, FFI buffers, leak detection, double-free/use-after-free risks, safety-checked illegal behavior, ReleaseFast safety assumptions, or Zig 0.15/0.16 memory API drift.
---

# Zig Memory Safety

## Operating Mode

Use this skill as a defect-finding workflow, not a generic Zig tutorial. Start by proving the active toolchain and project pin:

```bash
zig version
test -f build.zig.zon && sed -n '1,120p' build.zig.zon
```

As of 2026-05-13, Zig `0.16.0` is the latest tagged release and `0.17.0-dev` builds are available upstream. Many production repos remain pinned to `0.15.x`; follow the repo pin unless the task is explicitly a migration.

## Memory Model

- Treat every allocation as a contract with one owner, one deinit/free path, and clear transfer semantics.
- Prefer passing `std.mem.Allocator` explicitly at construction boundaries. Avoid hidden globals and allocator selection inside low-level helpers.
- Distinguish borrowed slices from owned buffers in names, docs, tests, and deinit behavior.
- Do not return slices or pointers into stack locals, temporary parser buffers, freed environment buffers, arena memory that dies before the caller, or reallocated containers.
- Use arenas only for bounded request/session lifetimes. In long-running loops, reset or deinit per iteration so arenas do not hide leaks.
- Prefer slices over many-item pointers because slices carry length and normal indexing is bounds-checked in safety-enabled modes. Treat slices as borrowed pointer-plus-length views, not owners.
- Treat `ArrayList.items` and similar container slices as invalidated after resize, append, deinit, or transfer.
- Treat `[*]T`, C pointers, `@ptrCast`, `@alignCast`, `@constCast`, packed/extern layout, and sentinel slices as review hotspots.

## Workflow

1. Map ownership before editing.
   Write down which object owns each buffer, which allocator created it, and who frees it. If this is unclear, fix the API boundary first.

2. Add a failing proof for the memory risk.
   Use `std.testing.allocator`, malformed input, error-path tests, or repeated-operation tests to expose leaks and lifetime bugs.

3. Implement with explicit cleanup.
   Use `errdefer` for partially initialized resources, `defer` for successful local cleanup, and a single `deinit` owner for structs. Avoid duplicate `errdefer` registrations for the same allocation.

4. Exercise error paths.
   Test allocation failure when practical, malformed input, short reads, missing fields, unknown enum values, and early returns after partial initialization.

5. Verify in the target safety mode.
   Run focused tests first, then the repo lane such as:

```bash
zig build test --summary all
```

If performance work requires `ReleaseFast`, keep a Debug or ReleaseSafe behavioral lane because safety checks are disabled by default in `ReleaseFast` and `ReleaseSmall`.

## Review Checklist

- No returned address of locals, temporary buffers, or slices from buffers freed before return.
- No stored borrowed slices from parsers, environment variables, command arguments, or file buffers unless the owner outlives the storage.
- No double-free from copied owning structs, duplicate `errdefer`, or container ownership confusion.
- No leak on every `try` edge after an allocation.
- No unchecked optional unwrap, error unwrap, alignment cast, enum cast, integer cast, or pointer cast on runtime input.
- No `catch unreachable` for file, network, JSON, CLI, FFI, allocator, or user-controlled input.
- No arena used as an unbounded cache.
- No FFI buffer used after the C owner frees or mutates it.
- No mutation of `slice.ptr` that can desynchronize pointer and length.

## Version Notes

- Zig `0.16.0` added a compile error for trivial returns of local addresses. Do not rely on this to catch non-trivial lifetime bugs.
- Zig `0.16.0` made `heap.ArenaAllocator` thread-safe and lock-free and removed `heap.ThreadSafe`; do not backport that assumption to `0.15.x` without checking the local stdlib.
- Zig `0.16.0` continues migration toward unmanaged containers. When porting from `0.15.x`, inspect container initialization and deinit ownership rather than applying search-and-replace fixes.
- Allocator names and defaults drift across releases. Use the repo-pinned docs for `DebugAllocator`, `GeneralPurposeAllocator`, `smp_allocator`, and any thread-safe wrappers.
- Runtime safety checks catch many illegal behaviors in safety-enabled modes, but they are not a substitute for ownership tests.

## Test Patterns

- Use `std.testing.allocator` for leak-detecting unit tests.
- Use `std.testing.FailingAllocator` or local failure injection when partial initialization or OOM cleanup is the risk.
- Use `std.heap.FixedBufferAllocator` for deterministic bounded-memory tests.
- Add repeated-operation tests for APIs that reuse arenas, internal buffers, or cached containers.

## Source Refresh

Before making version-sensitive claims, refresh primary sources:

- `https://ziglang.org/download/`
- `https://ziglang.org/documentation/master/`
- `https://ziglang.org/download/0.16.0/release-notes.html`
