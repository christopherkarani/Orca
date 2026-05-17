# Memory And Lifetime

## Allocator Policy

- Libraries accept `std.mem.Allocator` from the caller.
- CLIs may use an arena for process-lifetime allocations, but long-running loops need bounded per-iteration ownership.
- Tests should use `std.testing.allocator` or another leak-detecting allocator.
- Use `FixedBufferAllocator` when the maximum size is bounded.
- Use `ArenaAllocator` for bulk lifetime groups; do not return arena-backed memory beyond arena lifetime.
- Use GPA/debug allocator in tools and tests to catch leaks and invalid frees when supported by the target Zig version.
- In Zig 0.16+, review container migration carefully: unmanaged containers usually move allocator ownership from the container into each operation or deinit call.
- In long-running code, cap arena lifetime by request/session/batch; process-lifetime arenas are only acceptable for short CLI runs.
- Avoid allocator fields in public structs unless the struct truly owns future allocations; hidden allocator capture makes ownership harder to audit.

## Ownership Contract

For every slice/pointer in a public function, decide and test:

- Borrowed input: caller owns, callee must not store beyond call.
- Owned output: caller must free with the allocator named in the API.
- Transferred input: callee takes responsibility and must deinit on all later paths.
- View into object: lifetime is tied to object and invalid after mutation/deinit.
- Static/comptime data: safe to keep, but must not be mutated.
- Caller-provided output buffer: callee writes into it and returns a slice view; caller owns the backing buffer and must keep it alive.
- Interned/shared data: central table owns memory; returned slices are invalidated by table deinit and sometimes by mutation.

Prefer names that make ownership visible:

```zig
pub fn readOwned(allocator: std.mem.Allocator, path: []const u8) ![]u8;
pub fn viewName(self: *const Item) []const u8;
pub fn deinit(self: *Item, allocator: std.mem.Allocator) void;
```

## Cleanup Patterns

Use `errdefer` immediately after acquisition:

```zig
const bytes = try allocator.alloc(u8, len);
errdefer allocator.free(bytes);

const parsed = try parse(bytes);
return parsed;
```

For structs with owned fields:

```zig
const Self = @This();

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    self.* = undefined;
}
```

Set to `undefined` after deinit only when it helps catch accidental reuse and the local codebase accepts that style.

## Common Bugs

- Returning slices into stack arrays, temporary parser buffers, env buffers, or freed arenas.
- Storing borrowed map keys from JSON/tokenizer buffers in long-lived maps.
- Double `errdefer` on the same allocation after ownership transfer.
- Freeing with a different allocator than the allocator used to allocate.
- Growing containers without a deinit path in all early returns.
- Using `catch unreachable` after allocation, I/O, parsing, or external process calls.
- Calling `toOwnedSlice` or equivalent ownership-transfer helpers without clearing the original container's deinit responsibility when the API requires it.
- Keeping pointers into `ArrayList`/hash-map storage across growth or rehash operations.
- Assuming `dupe` copies nested pointed-to data; it only copies the slice contents.
- Returning a slice of a fixed local buffer after formatting.

## Container Rules

- Deinit every container on all error paths unless ownership is transferred.
- Duplicate keys and values when a map must outlive the parser/tokenizer buffer.
- Avoid storing pointers to elements in resizable containers unless growth is impossible or the pointer is short-lived.
- For unmanaged containers, pass the allocator consistently to init/grow/deinit operations and document which allocator owns storage.
- For hash maps keyed by slices, define whether keys are borrowed or owned and test parser-buffer deinit before lookup.

## Tests

- Add leak-detecting tests for APIs that allocate.
- Add malformed-input tests that fail after partial allocation.
- Add ownership-transfer tests: success path, early parse failure, and deinit idempotence only if the API promises idempotence.
- Add target-specific tests when allocator behavior depends on libc, OS APIs, or page size.
- Add mutation-after-view tests when APIs return views into internal storage.
- Add oversize-input tests for bounded buffers and arena-backed parsers.
