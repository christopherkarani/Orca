# Errors And APIs

## Error Sets

- Prefer precise error sets for library APIs when the set is stable and meaningful.
- Use inferred `!T` internally when it keeps code simple and errors do not cross a stable boundary.
- Avoid `anyerror` in public APIs unless the boundary intentionally hides implementation details.
- Keep domain error sets stable at package boundaries; adding/removing public errors can be a semver-visible change.
- Translate low-level errors at subsystem boundaries:

```zig
return parseConfig(bytes) catch |err| switch (err) {
    error.UnknownKey => error.InvalidConfig,
    error.OutOfMemory => error.OutOfMemory,
    else => error.InvalidConfig,
};
```

Do not erase `OutOfMemory` into a generic parse error unless the project has an explicit policy for that boundary.

## Optionals

- Use `?T` for absence that is expected and not itself an error.
- Use `error.MissingField` or a domain error when absence violates input schema.
- Prefer `if (maybe) |value|` and `orelse` over force unwraps.
- Do not use null as an implicit "not loaded because parse failed" state; preserve the error.
- Avoid `.?` outside tests or genuinely proven invariants. External input must use explicit error conversion.

## Result Shapes

- Use `!T` when the operation either succeeds with a value or fails.
- Use `?T` for lookup-style absence.
- Use `!?T` only when absence and failure are both meaningful and tests cover both.
- Use tagged unions when outcomes need payloads such as `allowed`, `denied(reason)`, `unsupported(feature)`, and `skipped(cause)`.
- Keep `skipped`, `unsupported`, `inconclusive`, and `failed` distinct in verification/reporting APIs.

## API Design

- Keep functions small enough that ownership and error behavior are inspectable.
- Put allocator parameters first or near the operation that allocates, matching local style.
- Separate parsing from policy decisions where possible.
- Return structured results, not formatted strings, from reusable libraries.
- Reserve text formatting for CLI/reporting boundaries.
- Keep public structs stable; use private fields plus methods when invariants matter.

## Boundary Rules

- External input parse functions should reject unknown fields when unknown fields alter security or safety meaning.
- CLI commands should return non-zero for unsupported or placeholder behavior.
- Public JSON output should be escaped through one tested path.
- Error messages should include enough context to fix the input but not leak secrets.
- CLI/library boundaries should translate rich internal errors into stable user-facing diagnostics without losing audit detail.
- Security-sensitive parsers should prefer fail-closed domain errors over fallback defaults.

## Review Questions

- Can the caller distinguish malformed input from denied policy from unsupported platform?
- Does `OutOfMemory` still propagate?
- Are missing and invalid fields different when the schema needs that distinction?
- Does every placeholder command fail until implemented?
- Do tests assert exact exit status where scripts depend on it?
- Can a future caller accidentally ignore a `bool` that should have been a domain result?
- Is the API forcing consumers to parse strings that could have been structured data?
