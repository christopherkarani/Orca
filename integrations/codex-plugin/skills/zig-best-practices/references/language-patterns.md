# Language Patterns

## Style And Shape

- Run `zig fmt` on changed Zig files.
- Prefer `const` until mutation is required.
- Keep declarations close to their use unless the module already has a different organization.
- Name types and functions by role, not implementation detail.
- Avoid redundant names: `Parser.parse`, not `JsonParser.parseJson`.
- Keep modules as structs by file: top-level declarations form the module API.

## Types

- Use enums/unions for finite states instead of stringly typed control flow.
- Use tagged unions for protocol messages, command variants, and parse results.
- Use `packed` and `extern` only when layout is a real ABI or wire-format contract.
- Use explicit enum backing types for wire/ABI surfaces; do not assume implicit tag size.
- For wire formats, prefer explicit integer sizes and endian-aware reads/writes.
- Keep sentinel-terminated slices only at C/string boundaries; use normal slices internally.
- Keep `[:0]const u8` boundaries narrow; convert to `[]const u8` once inside normal Zig code when sentinel behavior is no longer needed.
- Prefer `std.BoundedArray`, fixed buffers, or validated lengths for small bounded collections; avoid heap allocation by habit.

## Comptime And Generics

- Use `comptime` for real static structure: type parameters, compile-time tables, feature flags, and generated parsers.
- Avoid comptime cleverness that makes errors worse or blocks normal debugging.
- Prefer generic functions that preserve simple call sites:

```zig
fn parseEnum(comptime T: type, text: []const u8) ?T {
    inline for (@typeInfo(T).@"enum".fields) |field| {
        if (std.mem.eql(u8, text, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}
```

- Do not return comptime-only values through runtime APIs.
- Avoid `anytype` in public APIs unless the accepted shape is documented and tested.
- Avoid reflection-heavy `@typeInfo` code when a small explicit table is clearer and gives better error messages.
- Use `inline for` only when the loop must be unrolled or inspect comptime structure.

## Numeric Conversions

- Treat integer casts as validation points. Prefer checked conversion or range tests before `@intCast`, `@truncate`, enum conversion, allocation size math, and slice indexing.
- Validate signed-to-unsigned conversions from external input.
- Keep byte order explicit with `std.mem.readInt`/`writeInt` or local helpers matched to the pinned Zig version.
- For floats, keep NaN/Inf behavior explicit when values affect policy, sorting, hashing, or serialization.

## Control Flow

- Use `try` for propagation, `catch |err| switch (err)` for boundary translation, and `errdefer` for partial construction cleanup.
- Use `defer` for unconditional cleanup in the same scope that acquired the resource.
- Use `unreachable` only for states proven impossible by type, not for external input.
- Use `orelse return error.X` when missing optional data is an error in the current contract.

## Data Layout And Parsing

- Treat all external bytes as hostile.
- Validate length before slicing.
- Validate enum tags before `@enumFromInt`.
- Validate alignment before pointer casts.
- Avoid pointer reinterpretation for untrusted data; decode into values.
- Prefer bounded buffers and explicit maximum sizes for CLIs, protocols, and file readers.
- Keep `@bitCast` for value reinterpretation where source and destination layouts are proven; do not use it to parse hostile byte streams.
- Add compile-time assertions for ABI or wire layout:

```zig
comptime {
    std.debug.assert(@sizeOf(Header) == 16);
    std.debug.assert(@alignOf(Header) == 4);
}
```
