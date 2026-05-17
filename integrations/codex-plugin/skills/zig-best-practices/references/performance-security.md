# Performance And Security

## Safety Modes

- Debug and ReleaseSafe keep runtime safety checks; ReleaseFast and ReleaseSmall disable many checks by default.
- Do not rely on safety checks for correctness. Validate untrusted input before indexing, casting, shifting, or enum conversion.
- Use `@setRuntimeSafety` sparingly and only with local proof.
- Keep `unreachable` for impossible internal states, never malformed external data.
- Audit code under ReleaseFast separately: unchecked arithmetic, unchecked indexing, and invalid enum/pointer assumptions can become memory safety bugs.
- Use `std.debug.assert` for internal invariants, not user-input validation that must survive optimized builds.

## Performance Workflow

1. Prove correctness with focused tests.
2. Add a benchmark or trace around the real hot path.
3. Run ReleaseFast separately.
4. Preserve same-output proof before and after optimization.
5. Keep safety and readability unless measurements justify the complexity.

Prefer algorithmic wins, bounded allocation, fewer copies, and layout clarity before pointer tricks.

Measure with representative data. Microbenchmarks are useful for regressions, but they do not prove end-to-end latency, cache behavior, allocator pressure, or syscall behavior.

## Allocation Performance

- Reuse buffers when lifetime is clear.
- Avoid per-token allocation in parsers.
- Use arenas for batch parse/build phases.
- Use fixed buffers for bounded outputs.
- Keep large allocations visible and fallible.
- Avoid accidental quadratic growth from repeated append/concat/format cycles.
- Reuse buffers only when doing so does not blur ownership or leak prior sensitive contents.

## Parser Security

- Bound nesting, input size, token count, line length, and output size.
- Reject unknown keys when policy/security meaning matters.
- Reject duplicate keys if the schema treats duplicates as ambiguous.
- Keep malformed, truncated, oversized, and random-byte fixtures.
- Avoid logging raw payloads that may contain secrets.
- Keep parsers iterative or depth-limited; recursive descent needs an explicit nesting cap.
- Treat JSON/YAML/TOML duplicate-key behavior as a policy decision, not a parser accident.

## Integer And Pointer Safety

- Check arithmetic that feeds allocation sizes or slice indexes.
- Use overflow builtins or checked patterns for user-controlled sizes.
- Validate shift amounts, enum tags, and union fields.
- Avoid pointer casts for external bytes.
- Validate alignment before casting and prefer decoding into values.
- Prefer checked math for `len * elem_size`, offset + length, and capacity growth derived from input.
- Add big-endian and unaligned-input review points for binary formats.

## Crypto And Secrets

- Use `std.crypto` primitives rather than custom crypto.
- Prefer authenticated encryption where confidentiality and integrity are both needed.
- Use constant-time comparison for secrets.
- Zeroize key material where the threat model requires it.
- Redact before persistence, including audit logs, JSON reports, panic context, and test output.
- Keep fake secrets synthetic and clearly marked in tests.
- Avoid timing leaks in authentication, token matching, and MAC comparisons.
- Do not invent randomness. Use the current `std.crypto.random`/OS entropy path for the pinned Zig version.
- Keep nonce uniqueness and key rotation as explicit API responsibilities.

## Security Review Prompts

- What can a malicious file, CLI arg, env var, path, network response, or child process make this code do?
- Are deny/default branches explicit?
- Does unsupported/inconclusive/skipped ever become pass?
- Is capability reporting honest about observe-only, wrapper-only, partial, and active enforcement?
- Can a clean checkout reproduce the claimed behavior?
- Are ReleaseFast assumptions covered by tests or explicit checks?
- Can malformed input consume unbounded CPU, memory, recursion depth, file descriptors, or child processes?
