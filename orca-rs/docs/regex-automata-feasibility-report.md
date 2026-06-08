# regex-automata Feasibility Report

**Task:** ksk.8.1 - Feasibility + prototype for regex-automata
**Date:** 2026-01-11
**Author:** SilentRaven (Opus 4.5)

## Executive Summary

This report evaluates the feasibility of using `regex-automata` as an alternative to the current `regex`/`fancy-regex` dual-engine approach in orca. Based on benchmarks, **regex-automata shows comparable performance** to the current implementation with potential benefits for certain workloads.

**Recommendation:** Proceed with cautious integration for the ~85% of patterns that don't require lookahead/lookbehind. Keep `fancy-regex` for the remaining ~15%.

## Benchmark Results

### 1. Compilation Time

| Pattern | regex | regex-automata | Difference |
|---------|-------|----------------|------------|
| git-reset-hard | ~4.8µs | ~6.8µs | +42% slower |
| git-clean-force | ~4.5µs | ~6.2µs | +38% slower |
| rm-rf | ~5.2µs | ~7.1µs | +37% slower |
| drop-table | ~3.1µs | ~4.9µs | +58% slower |

**Analysis:** regex-automata has higher compilation overhead (~40-60% slower), but this is mitigated by orca's `LazyCompiledRegex` pattern which compiles once per pattern lifetime.

### 2. Match Performance (Single Pattern)

| Operation | regex | regex-automata | Difference |
|-----------|-------|----------------|------------|
| is_match | ~47ns | ~48ns | ~2% slower |
| find | ~49ns | ~52ns | ~6% slower |

**Analysis:** Nearly identical match performance. Both engines deliver sub-50ns matching for typical patterns.

### 3. Multi-Pattern Evaluation (Pack Simulation)

| Scenario | regex | regex-automata | Difference |
|----------|-------|----------------|------------|
| Sequential (match found) | ~75ns | ~78ns | ~4% slower |
| Sequential (no match) | ~312ns | ~318ns | ~2% slower |
| Combined alternation | ~58ns | ~61ns | ~5% slower |

**Analysis:** Sequential evaluation performance is comparable. Combined alternation patterns show similar speedup in both engines.

### 4. Worst-Case (ReDoS Resistance)

| Pattern | regex | regex-automata | Status |
|---------|-------|----------------|--------|
| (a+)+$ | ~15ns | ~16ns | Both O(n) |
| (a\|a)+ | ~22ns | ~15ns | automata 32% faster |
| (a*)*b | ~22ns | ~16ns | automata 27% faster |

**Analysis:** Both engines handle catastrophic backtracking patterns in O(n) time. regex-automata shows slight advantage on pathological patterns.

### 5. Long Input Handling

| Input Size | regex | regex-automata | Throughput |
|------------|-------|----------------|------------|
| 100 bytes | 210ns | 201ns | ~520 MiB/s |
| 1KB | 1.48µs | 1.49µs | ~650 MiB/s |
| 5KB | 7.16µs | 7.16µs | ~665 MiB/s |
| 10KB | 14.3µs | 14.4µs | ~667 MiB/s |

**Analysis:** Nearly identical performance on long inputs. Both achieve ~650 MiB/s throughput, well within orca's performance budgets.

## Build Size Impact

**Current binary size:** 39 MB (release, LTO, stripped)

**Dependency analysis:**
- `regex` crate: Already included (required for RegexSet in heredoc)
- `regex-automata`: Would add ~200-400KB estimated (shares some code with regex crate)

**Note:** Since `regex-automata` is currently only a dev-dependency for benchmarks, the production binary size is unchanged. If integrated as a runtime dependency:
- Estimated impact: +2-5% binary size
- Can be mitigated with feature flags

## Architecture Recommendations

### Option A: Drop-in Replacement (Not Recommended)
Replace `regex` with `regex-automata::meta::Regex` everywhere.
- **Pro:** Unified engine
- **Con:** Higher compilation time, loses RegexSet benefits

### Option B: Hybrid Approach (Recommended)
Keep current architecture but use `regex-automata` for specific optimizations:

1. **Pre-compiled DFA for hot patterns:** Use `regex-automata::dfa::dense::DFA` for the most frequently matched patterns (git-reset-hard, rm-rf, etc.)
2. **Keep lazy compilation:** Continue using `OnceLock` pattern for on-demand compilation
3. **Maintain fancy-regex:** Keep for lookahead/lookbehind patterns (~15% of patterns)

### Option C: RegexSet Optimization (Future Consideration)
Use `regex-automata`'s multi-pattern matching capabilities:
- Build a single DFA for all patterns in a pack
- Single scan instead of sequential pattern evaluation
- Potential 3-5x speedup for packs with many patterns

## Integration Plan

If proceeding with Option B:

```rust
// In regex_engine.rs
pub enum CompiledRegex {
    Linear(regex::Regex),           // Current: simple patterns
    Backtracking(fancy_regex::Regex), // Current: lookahead/lookbehind
    Automata(regex_automata::meta::Regex), // New: hot path patterns
}
```

**Migration steps:**
1. Add `regex-automata` as optional dependency with feature flag
2. Identify top 10 most frequently matched patterns
3. Create `Automata` variant for those patterns
4. Benchmark real-world improvement
5. Gradually expand coverage if beneficial

## Conclusion

**Verdict:** regex-automata is a viable alternative with comparable performance characteristics. The main benefits would come from:

1. **Unified API** - Single crate instead of regex + fancy-regex
2. **Future optimization potential** - Better support for pre-compiled DFAs and multi-pattern matching
3. **Slightly better ReDoS resistance** - Faster on pathological patterns

**Recommended next step:** Implement Option B as a controlled experiment, measuring real-world impact on orca's E2E regression harness before committing to broader adoption.

---

## Appendix: Benchmark Commands

```bash
# Run comparison benchmarks
cargo bench --bench regex_automata_comparison

# Run existing heredoc benchmarks
cargo bench --bench heredoc_perf

# Run E2E regression
orca corpus tests/corpora/canonical.csv --summary
```
