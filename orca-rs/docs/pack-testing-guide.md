# Pack Testing Guide

This guide outlines the testing framework and best practices for creating and maintaining packs in `orca_rs`.

## Philosophy

- **Safety First**: We prefer blocking a safe command (false positive) over allowing a destructive one (false negative).
- **Specificity**: Patterns should match specific dangerous flags/subcommands, not just the tool name.
- **Coverage**: Every pattern must be tested.
- **Performance**: Regexes must be efficient (avoid catastrophic backtracking).

## The Test Framework

We provide a `validate_pack` helper that automates structural checks.

```rust
use crate::packs::test_helpers::*;

#[test]
fn test_pack_creation() {
    let pack = my_pack::create_pack();
    validate_pack(&pack); // Checks ID, patterns, keywords, etc.
}
```

### Validation Checks

`validate_pack` enforces:
1.  **ID Format**: Lowercase, dots, underscores, digits.
2.  **Required Fields**: Name, description, keywords (at least one).
3.  **Pattern Compilation**: All regexes must compile.
4.  **Reasons**: All destructive patterns must have a reason.
5.  **Uniqueness**: All pattern names must be unique within the pack.

## Writing Tests

Use `assert_blocks` and `assert_allows` for clear, readable tests.

### Destructive Patterns

```rust
#[test]
fn test_destructive_prune() {
    let pack = my_pack::create_pack();
    assert_blocks(&pack, "docker system prune", "removes all unused");
}
```

### Safe Patterns

```rust
#[test]
fn test_safe_ps() {
    let pack = my_pack::create_pack();
    assert_allows(&pack, "docker ps");
}
```

### Specificity (False Positives)

Verify that unrelated commands are not blocked.

```rust
#[test]
fn test_specificity() {
    let pack = my_pack::create_pack();
    assert_no_match(&pack, "echo docker"); // Keyword in argument shouldn't match
}
```

## Performance Testing

Ensure your patterns don't hang on large inputs.

```rust
#[test]
fn test_performance() {
    let pack = my_pack::create_pack();
    assert_matches_within_budget(&pack, "docker run ...");
}
```

## Checklist

- [ ] `validate_pack` passes.
- [ ] Every destructive pattern has a `test_blocks` case.
- [ ] Every safe pattern has a `test_allows` case.
- [ ] "Edge case" inputs (quotes, whitespace) are tested.
- [ ] Performance test included.