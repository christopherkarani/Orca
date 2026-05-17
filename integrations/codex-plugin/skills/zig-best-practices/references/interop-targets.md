# Interop And Targets

## C Interop

- Use `extern` and `export` for ABI boundaries.
- Use C integer types (`c_int`, `c_uint`, etc.) at ABI edges.
- Use `anyopaque` for C `void *` when the pointee is intentionally opaque.
- Convert C pointers into safer Zig optionals/slices at the boundary.
- Do not expose Zig-only pointer attributes to C APIs.
- Keep ownership rules for C-allocated memory explicit: who allocates, who frees, with which allocator.
- Treat `[*c]T`, `?*T`, `[*]T`, and `[]T` as different contracts; convert once at the edge after null and length validation.
- Do not pass Zig slices to C as if they were null-terminated strings; allocate or validate sentinel termination.
- Keep callbacks small and exception-free: no unwinding through C, no hidden allocator lifetime assumptions.
- Pair every exported allocation function with an exported free/deinit function when C callers own returned memory.

## translate-c And @cImport

- Prefer build-system-managed C imports for repeatable builds, especially for 0.16+.
- Avoid ad hoc `@cImport` changes in source when the build graph should own include paths, defines, and target-specific flags.
- Check generated translations when C macros, packed structs, bitfields, or platform typedefs are involved.
- Add ABI smoke tests for exported symbols and struct sizes when the C boundary is public.
- Header drift is a release bug. Diff generated/public headers and Zig exported declarations together when changing ABI.

## Linking

- Prefer vendored or build-system-provided C libraries for reproducible cross-builds.
- Use system libraries only when that is the project contract.
- Gate libc use by target and document it.
- Verify Linux, macOS, Windows, and freestanding/WASI assumptions separately.

## Cross-Compilation

- Run target compile checks for every claimed target:

```bash
zig build test -Dtarget=x86_64-linux --summary all
zig build -Dtarget=aarch64-linux --summary all
```

Adjust target triples to the project.

- Do not count cross-compile success as runtime proof.
- Avoid early returns in `build.zig` that make target checks look green while skipping real work.
- Check endian, alignment, pointer width, filesystem, process, and libc differences.
- Check path separators, executable suffixes, environment variable case sensitivity, line endings, socket behavior, and signal/process behavior.
- Keep OS support claims aligned with Zig's tier/support table and the project's own CI.

## Embedded, WASI, Freestanding

- Avoid hidden heap allocation unless the target provides an allocator.
- Keep panic, logging, time, filesystem, and process dependencies target-gated.
- Use explicit exports and no-entry builds for wasm/freestanding where appropriate.
- Keep tests separable between host-only and target-compatible logic.
- Keep panic/log/time/random/filesystem dependencies injectable or target-gated.
