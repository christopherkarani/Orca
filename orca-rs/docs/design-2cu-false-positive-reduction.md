# Design: False Positive Reduction for String Arguments

## Status: DESIGN COMPLETE
**Author:** SunnyMill
**Date:** 2026-01-08
**Bead:** git_safety_guard-2cu
**Reviewed:** Pending

---

## 1. Executive Summary

This design formalizes the execution-context model and Safe String-Argument Registry already implemented in `src/context.rs`. It defines:
1. When to skip pattern matching (safe data contexts)
2. How to integrate context classification into the evaluator pipeline
3. Performance budget and test matrix

---

## 2. Execution Context Model

### 2.1 SpanKind Enum (Existing Implementation)

The classification uses six distinct context types:

| SpanKind | Pattern Check? | Description |
|----------|---------------|-------------|
| **Executed** | YES | Command word or unquoted argument |
| **InlineCode** | YES | Content after -c/-e flags (bash -c, python -c) |
| **HeredocBody** | YES | Heredoc content (escalate to Tier 2/3) |
| **Unknown** | YES | Ambiguous context (conservative treatment) |
| **Argument** | NO* | Double-quoted argument to non-code command |
| **Data** | NO | Single-quoted string (no substitution possible) |

*Argument spans MAY have pattern matching applied at lower priority; current design skips them.

### 2.2 Decision Rules

1. **Ambiguity → Executed**: If classification is uncertain, treat as executable
2. **Single quotes are always safe**: No variable expansion or command substitution
3. **Double quotes require analysis**: Check for $() and backticks inside
4. **Inline code commands (-c/-e/-r)**: Always treat following argument as code

### 2.3 Supported Inline Code Commands

```rust
inline_code_commands: &[
    "bash", "sh", "zsh", "ksh", "dash",  // shells with -c
    "python", "python3", "python2",       // python with -c
    "node", "nodejs",                     // node with -e
    "ruby", "perl", "php", "lua",         // various -e/-r
]
```

---

## 3. Safe String-Argument Registry

### 3.1 Scope Definition

The registry maintains TWO categories:

#### 3.1.1 All-Args-Data Commands
Commands where ALL arguments are purely printed output:
- `echo`
- `printf`

#### 3.1.2 Flag-Data Pairs
Specific command+flag combinations where the flag's value is documentation/data:

| Command | Flags | Rationale |
|---------|-------|-----------|
| **git** | -m, --message | Commit/tag messages |
| **bd** | --description, --title, --notes, --reason | Issue tracking metadata |
| **grep** | -e, --regexp, -F, --fixed-strings | Search patterns |
| **rg** | -e, --regexp, --fixed-strings | Search patterns |
| **gh** | -t, --title, -b, --body, -m, --message | GitHub CLI metadata |
| **cargo** | --message | Package metadata |
| **npm** | --message | Package metadata |

### 3.2 Conservative Extension Rules

New entries MUST satisfy ALL criteria:
1. Arguments are NEVER executed by the shell
2. Use case documented with real-world false positive example
3. Test case demonstrating both the false positive and the fix
4. No flag collision with code-executing flags (e.g., never add bash -c)

---

## 4. Integration Strategy

### 4.1 Two-Phase Approach

**Phase 1 (Current):** Sanitization before pattern matching
```
command → sanitize_for_pattern_matching() → sanitized_command → pattern_match()
```

**Phase 2 (Future):** Span-aware pattern matching
```
command → classify_command() → spans[] → match_executable_spans_only()
```

### 4.2 Integration Point in Evaluator

Modify `evaluate_command_with_legacy()` in `src/evaluator.rs`:

```rust
// Before Step 5 (legacy safe patterns):
let sanitized = context::sanitize_for_pattern_matching(&normalized);

// Use sanitized for legacy pattern matching
for pattern in safe_patterns {
    if pattern.is_match(&sanitized) { ... }
}
for pattern in destructive_patterns {
    if pattern.is_match(&sanitized) { ... }
}

// Pack matching also uses sanitized
REGISTRY.check_command(&sanitized, &enabled_packs)
```

### 4.3 Backward Compatibility

- Original command preserved for logging/explain output
- Sanitized command used only for pattern matching
- No behavioral change for commands without safe-data arguments

---

## 5. Test Matrix

### 5.1 Must-ALLOW Cases (False Positives to Eliminate)

| Command | Contains | Why Safe |
|---------|----------|----------|
| `git commit -m "Fix reset --hard detection"` | reset --hard | Message is data |
| `git commit -m "docs: git reset --hard"` | reset --hard | Message is data |
| `bd create --description="blocks git clean"` | git clean | Description is data |
| `bd update --notes="test git clean -f"` | clean -f | Notes is data |
| `echo "example: git reset --hard"` | reset --hard | echo args are data |
| `printf "git push --force %s"` | push --force | printf args are data |
| `grep "reset --hard" patterns.txt` | reset --hard | First positional arg is pattern |
| `rg -e "git push --force" src/` | push --force | -e flag is pattern |
| `rg "git clean -fd" --json` | clean -fd | First positional arg is pattern |
| `gh issue create -t "Fix git clean bug"` | git clean | Title is data |
| `gh pr create -b "Updates git reset"` | reset | Body is data |

**Note:** `git log --grep` is NOT currently in SafeStringRegistry - this is a registry gap to address in fpim.

### 5.2 Must-BLOCK Cases (True Positives to Preserve)

| Command | Contains | Why Dangerous |
|---------|----------|---------------|
| `rm -rf /home/user` | rm -rf | Direct execution |
| `git reset --hard HEAD` | reset --hard | Direct git command |
| `git push --force origin main` | push --force | Direct git command |
| `bash -c "git reset --hard"` | reset --hard | Inline code execution |
| `python -c "import os; os.system('rm')"` | os.system | Inline code execution |
| `sh -c 'git clean -fd'` | clean -fd | Inline code execution |
| `echo $(git reset --hard)` | reset --hard | Command substitution |
| `git commit -m "$(git push --force)"` | push --force | Subst in message |

### 5.3 Edge Cases

| Command | Decision | Rationale |
|---------|----------|-----------|
| `git commit -m 'reset --hard'` | ALLOW | Single quotes = data |
| `git commit -m "$(date)"` | ALLOW* | Substitution but safe content |
| `echo "normal text"` | ALLOW | No dangerous content |
| `bd create --title="test" && git clean` | BLOCK | After && is executed |
| `grep "pattern" src/ \| xargs rm` | per-segment | Pipe creates segments |

*Note: `$(date)` contains substitution but the command itself (`date`) is safe. However, conservative implementations may block any substitution in arguments.

---

## 6. Performance Budget

### 6.1 Targets

| Operation | Budget | Measured |
|-----------|--------|----------|
| Context classification | <100μs | ~2μs avg |
| Sanitization | <100μs | ~5μs avg |
| Full pipeline addition | <200μs | <50μs typ |

### 6.2 Constraints

1. No per-command regex compilation for sanitization
2. Tokenization is O(n) single-pass
3. SafeStringRegistry uses static arrays (constant-time lookup)
4. Cow<str> avoids allocation when no sanitization needed

### 6.3 Validation

```rust
#[test]
fn test_performance_typical_commands() {
    // Assert <100μs per command average
    assert!(avg_microseconds < 100.0);
}
```

---

## 7. Implementation Status

| Component | Status | Location |
|-----------|--------|----------|
| SpanKind enum | ✅ Implemented | context.rs:27-56 |
| ContextClassifier | ✅ Implemented | context.rs:220-497 |
| SafeStringRegistry | ✅ Implemented | context.rs:535-672 |
| sanitize_for_pattern_matching | ✅ Implemented | context.rs:722-870 |
| Unit tests | ✅ 50+ tests | context.rs:1278-1873 |
| **Evaluator integration** | ❌ NOT DONE | evaluator.rs (needs update) |
| E2E tests | ⚠️ Partial | e2e_test.sh |

---

### 7.1 E2E Coverage Matrix (Gap Analysis)

This matrix captures current E2E coverage across hook + CLI + scan flows. It
highlights gaps and the script(s) that provide coverage today.

| Area | Hook | CLI | Scan | Evidence | Notes / Gaps |
|------|------|-----|------|----------|--------------|
| Hook allow/deny core (git/rm) | ✅ | — | — | `scripts/e2e_test.sh` | Broad allow/deny cases + path normalization |
| Policy modes (warn/log/deny) | ✅ | — | — | `scripts/e2e_test.sh` | Uses `ORCA_POLICY_DEFAULT_MODE` |
| Pack enablement (non-core packs) | ✅ | — | — | `scripts/e2e_test.sh` | Docker/K8s/DB/infra packs via `ORCA_PACKS` |
| Non-Bash tools ignored | ✅ | — | — | `scripts/e2e_test.sh` | Read/Write/Edit/Grep/Glob |
| Malformed hook input | ✅ | — | — | `scripts/e2e_test.sh` | Invalid JSON, missing fields |
| Allowlist (project layer) | ✅ | — | — | `scripts/e2e_test.sh` | Rule allow/expire/conditions |
| Allowlist layering (user/system) | ❌ | — | — | — | No precedence tests across project/user/system |
| Config precedence (env/project/user/system) | ❌ | ❌ | ❌ | — | Needs hermetic HOME/XDG + temp project |
| Config overrides (allow/block regex) | ❌ | ❌ | ❌ | — | No E2E that validates override regex behavior |
| Doctor (install/uninstall + health) | — | ❌ | — | — | No E2E coverage for settings.json edits |
| `orca test` CLI | — | ❌ | — | — | No E2E for CLI test command behavior |
| `orca explain` formats | — | ❌ | — | — | Pretty/compact/json not validated |
| `orca simulate` formats | — | ❌ | — | — | Parser/output not exercised end-to-end |
| Scan `--staged` (basic) | — | — | ✅ | `scripts/scan_precommit_e2e.sh` | Empty/destructive/data-only/mixed |
| Scan `--git-diff` (CI) | — | — | ✅ | `scripts/scan_gitdiff_e2e.sh` | Add/modify/rename/delete + ordering |
| Scan output schema + determinism | — | — | ✅ | `scripts/scan_precommit_e2e.sh` | JSON schema + ordering |
| Scan extractors: GitHub Actions | — | — | ✅ | `scripts/scan_precommit_e2e.sh` | `run:` extraction |
| Scan `--paths` include/exclude | — | — | ❌ | — | No E2E for include/exclude glob behavior |
| Scan install/uninstall pre-commit | — | — | ❌ | — | No E2E for hook install/uninstall |
| Scan limits (max_findings/size/truncate) | — | — | ❌ | — | No E2E for caps/truncation |
| Heredoc detection (multi-lang) | ⚠️ | — | — | `scripts/e2e_test.sh` | Tests present but depend on heredoc epic |
| Execution-context sanitization | ⚠️ | — | — | `scripts/e2e_test.sh` | Tests present but depend on t8x epic |

**Gap priorities**
1. **P0**: allowlist layering, config precedence, doctor install/uninstall (correctness + safety).
2. **P1**: explain/simulate CLI coverage; scan limits + `--paths`; scan pre-commit install/uninstall.
3. **P2**: expand path/quoting/encoding matrix + cross-platform variants; add `orca test` CLI E2E.

### 7.2 Proposed E2E Additions (Scripts/Tests)

These are concrete, minimal E2E additions to close the gaps above.

**P0 (must-have)**
- Extend `scripts/e2e_test.sh` to cover allowlist layering (project/user/system precedence) using a temp repo + temp HOME/XDG_CONFIG_HOME. Rationale: allowlist correctness gates safe bypasses.
- Add a config precedence E2E harness (new `scripts/e2e_config_precedence.sh` or a new section in `scripts/e2e_test.sh`). Rationale: env/project/user/system precedence bugs silently misconfigure protection.
- Add a doctor E2E harness (e.g., `scripts/doctor_e2e.sh`) that operates on a temp `settings.json`. Rationale: installation health checks must be reliable and safe.

**P1 (high)**
- Add `orca explain` E2E coverage (pretty/compact/json) and validate stable pack + pattern IDs. Rationale: users depend on explain for debugging and allowlist rules.
- Add `orca simulate` E2E coverage for parser and output formats, including truncation/redaction. Rationale: simulate is the onboarding/debugging path for large command corpora.
- Add `orca scan --paths` E2E coverage with include/exclude globs + fail-on thresholds. Rationale: CI workflows typically use paths, not just staged/diff.
- Extend scan E2E to cover `max_findings`, `max_file_size`, and `truncate`. Rationale: limits are safety valves and must be deterministic.

**P2 (nice-to-have)**
- Expand path/quoting/encoding matrix in `scripts/e2e_test.sh` for path normalization and quoting edge cases. Rationale: reduces false positives and platform drift.
- Add a small `orca test` CLI E2E section to validate CLI parity with hook decisions. Rationale: parity prevents confusion during debugging.

---

## 8. Remaining Work

### 8.1 High Priority
1. Integrate `sanitize_for_pattern_matching()` into evaluator pipeline
2. Add E2E tests for false positive scenarios from Section 5.1
3. Document in README/help output that string arguments are context-aware

### 8.2 Medium Priority
4. Consider extending registry for more commands (jq, sed patterns, awk scripts)
5. Add `orca explain` output showing sanitization decisions

### 8.3 Low Priority
6. Investigate tree-sitter-bash for more accurate tokenization
7. Add configuration for custom safe-flag entries

---

## 9. References

- git_safety_guard-t8x: Epic: False Positive Immunity
- git_safety_guard-fpim: Implement false positive reduction (in_progress by PurpleRobin)
- git_safety_guard-2ta: Two-tier detection architecture (in_progress by RusticPuma)
- src/context.rs: Full implementation

---

## 10. Appendix: Counterexamples (What NOT to Add)

These should NEVER be in SafeStringRegistry:
- `bash -c` → Executes code
- `python -c` → Executes code
- `xargs` → Can execute arbitrary commands
- `eval` → Executes arbitrary string
- `exec` → Replaces process
- `source` / `.` → Executes script file

---

## 11. Meta-Note: Ironic False Positive

While writing this design document, the command `bd update --notes="..."` was blocked because the notes content contained dangerous patterns being documented. This is the exact problem this design solves - the ACFS hook (Python predecessor) doesn't have context awareness, but orca with this design will allow such documentation commands.
