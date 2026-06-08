# Design: Lazy Pack Registry + Lazy Regex Compilation

Goal: eliminate eager regex compilation from the hot path while preserving
behavior and attribution exactly (isomorphism).

## Goals

- List packs/keywords without compiling regex.
- Allow-path quick-reject without compiling regex.
- Compile regex only for enabled packs actually evaluated.
- Preserve ordering, attribution, and fail-open behavior.

## Non-Goals

- Changing patterns, policy, or allow/deny semantics.
- Altering pack ordering or safe-before-destructive logic.
- Introducing a daemon or persistent service.

## Proposed Types (metadata-only packs)

### PackSpec

```rust
pub struct PackSpec {
    pub id: &'static str,
    pub name: &'static str,
    pub description: &'static str,
    pub keywords: &'static [&'static str],
    pub safe_patterns: &'static [SafePatternSpec],
    pub destructive_patterns: &'static [DestructivePatternSpec],
}
```

### SafePatternSpec

```rust
pub struct SafePatternSpec {
    pub name: &'static str,
    pub pattern: &'static str,
    pub compiled: std::sync::OnceLock<CompiledRegex>,
}
```

### DestructivePatternSpec

```rust
pub struct DestructivePatternSpec {
    pub name: Option<&'static str>,
    pub pattern: &'static str,
    pub reason: &'static str,
    pub severity: Severity,
    pub compiled: std::sync::OnceLock<CompiledRegex>,
}
```

### Lazy Compile API

```rust
impl SafePatternSpec {
    pub fn is_match(&self, haystack: &str) -> bool;
    pub fn find_span(&self, haystack: &str) -> Option<(usize, usize)>;
}

impl DestructivePatternSpec {
    pub fn is_match(&self, haystack: &str) -> bool;
    pub fn find_span(&self, haystack: &str) -> Option<(usize, usize)>;
}
```

- `CompiledRegex` comes from `src/packs/regex_engine.rs` and auto-selects
  linear vs backtracking engine.
- `OnceLock::get_or_init` is used on first match attempt only.

## Registry Structure

`PackRegistry` stores only `PackSpec` (no compiled regex).

Derived data:
- `keywords` list is computed from `PackSpec.keywords`.
- `expand_enabled_ordered` uses pack IDs only.

Evaluation:
- **Safe pass:** iterate safe patterns across enabled packs; on first match
  return allow.
- **Destructive pass:** iterate destructive patterns across enabled packs;
  return the first match (respecting severity/mode).

Compilation happens only when a pattern is actually evaluated.

## Keyword Index + Candidate Pack Selection

This section specifies the keyword gating semantics that the index must
preserve. It applies to quick-reject and any future "candidate pack"
pre-filter, and is designed to be **conservative** (never more restrictive
than the legacy `pack.might_match`).

### Executable spans (context classification)

Keyword gating operates on **executable spans** only, derived from
`context::classify_command()`:

- The command is tokenized into spans tagged as `Executed`, `Argument`,
  `InlineCode`, or `Comment`.
- **Only `Executed` spans are searched for keywords.**
  - This avoids keyword hits inside data-only arguments, comments, or inline
    code examples.
- If no executable spans are detected, keyword gating treats the command as
  non-executable content and **quick-rejects** (safe to skip pack evaluation).

### Word-boundary matching

Keyword matching is **token-aware** within executable spans:

- A keyword match is valid only when it respects word boundaries for ASCII
  word characters (`[A-Za-z0-9_]`).
- Boundary rules are based on the keyword itself:
  - If the keyword begins with a word character, the preceding byte must be
    non-word or span start.
  - If the keyword ends with a word character, the following byte must be
    non-word or span end.
  - Keywords that begin/end with non-word characters do **not** require a
    boundary on that side (e.g., `/usr/bin/git` or `--flag`).
- Substring matches inside longer tokens **do not** count
  (e.g., `"cat .gitignore"` does not match `git`).

### Candidate pack selection (superset rule)

Candidate selection must be **no more restrictive** than the current
`pack.might_match` behavior. It may be more permissive, but never stricter:

1. **Fast substring prefilter (optional)**: use SIMD substring search across
   the raw command to avoid expensive classification when no keywords appear.
2. **Normalized executable scan**: if any keyword survives the span + boundary
   checks, **include** that pack in the candidate set.
3. **Superset guarantee**: if `pack.might_match(cmd)` would return `true`,
   the candidate set **must include** that pack.

### Normalization + fallback behavior

Keyword gating should run on a **normalized** view of the command:

- Strip wrapper prefixes (`sudo`, `env`, `command`, leading backslash).
- Dequote only **executed command words** (arguments remain untouched).
- Strip common absolute paths (`/usr/bin/git` → `git`).

Fallbacks must remain conservative:

- If **no keywords are configured**, do **not** quick-reject; evaluate packs.
- If normalization produces an **owned** string (wrapper stripped/dequoted),
  use the normalized value for scanning.
- If normalization cannot safely slice (e.g., tokenizer failure),
  treat the original command as the scan source (fail open).

### Validation mapping

Add tests that explicitly assert:

- Word-boundary semantics (`git` vs `gitignore`, `/usr/bin/git`).
- Executable-span filtering (keywords in comments/strings do not match).
- Candidate-pack superset behavior vs `pack.might_match`.
- Empty keyword list disables quick-reject.

## Isomorphism Guarantees

1) **Ordering unchanged**
   - Same `expand_enabled_ordered` tier + lexicographic sort.
2) **Safe-before-destructive unchanged**
   - Two-pass evaluation preserved.
3) **Attribution unchanged**
   - Pack ID and pattern name sourced from the same specs; no renaming.
4) **Allowlist scope unchanged**
   - Allowlisting still bypasses only the matched rule, not the pack.
5) **Fail-open unchanged**
   - Regex execution errors still treated as non-match.
6) **Decision parity**
   - For any command, the first matching rule (by order) and its reason are
     identical to the eager-compile version.

## Handling Compile Errors (Parity)

Current behavior panics early on invalid patterns due to `Regex::new(...).expect`.

With lazy compilation, compile errors would shift to first use. To preserve
"invalid patterns are caught immediately" in dev/test without penalizing
production:

- Add a test `all_pack_patterns_compile` that explicitly compiles every
  pattern under `#[cfg(test)]`.
- Optional CLI: `orca packs --validate` to force compile all patterns.

## Migration Plan (Phased)

1) **Introduce specs + lazy regex primitive**
   - Add `SafePatternSpec` / `DestructivePatternSpec` with `OnceLock`.
   - Reuse `CompiledRegex` (no behavior change yet).

2) **Refactor pack definitions**
   - Replace `Vec<SafePattern>` with static arrays of `SafePatternSpec`.
   - Replace `Vec<DestructivePattern>` with static arrays of `DestructivePatternSpec`.

3) **Registry metadata-only**
   - `PackRegistry::new` builds only `PackSpec` and keywords.
   - No regex compilation on init.

4) **Evaluator wiring**
   - Safe/destructive passes call `spec.is_match()` which compiles lazily.

5) **Parity guardrails**
   - Add `all_pack_patterns_compile` test.
   - Add regression corpus parity test: eager vs lazy output identical.

## Integration Points

- `src/packs/mod.rs`: Pack/Pattern type refactor and registry construction.
- `src/packs/regex_engine.rs`: Lazy compile backing type (`CompiledRegex`).
- `src/evaluator.rs`: Pattern match calls use lazy spec API.
- `src/main.rs`: Pack keyword gating remains metadata-only.

## Success Criteria

- `orca packs --enabled` is metadata-only (no regex compile).
- Hook allow path performs no regex compilation.
- Golden/e2e parity unchanged for allow/deny outcomes and reasons.

## Profiling Workflow (gprofng fallback)

When `perf` is blocked (e.g., `perf_event_paranoid=4`), use `gprofng` to
capture repeatable CPU + heap profiles. The goal is to surface inclusive
time hotspots for pack registry initialization and regex compilation.

### CPU hotspot (startup-heavy path)

Use a short loop to stabilize measurements and keep the command focused on
registry init (`orca packs --enabled`):

```bash
gprofng collect app -o /tmp/orca_packs_loop_cpu.er -F '=orca' -p on \
  sh -c 'for i in $(seq 1 20); do ./target/release/orca packs --enabled >/dev/null; done'

gprofng display text -functions /tmp/orca_packs_loop_cpu.er | head -n 50
```

### Heap profile

```bash
gprofng collect app -o /tmp/orca_packs_heap.er -H on -p on \
  ./target/release/orca packs --enabled >/dev/null
```

### I/O sanity fallback

If gprofng cannot initialize, a quick I/O profile can still validate that the
binary is running cleanly:

```bash
strace -c -f ./target/release/orca packs --enabled >/dev/null
```

### Comparing before/after

1. Record the command, binary path, and git commit SHA.
2. Save the `.er` artifacts with a timestamp (`/tmp/orca_packs_*_<date>.er`).
3. Compare the top 20 functions (inclusive time) to confirm hotspots moved.
