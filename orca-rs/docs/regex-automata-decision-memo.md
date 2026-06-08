# regex-automata Decision Memo

**Task:** ksk.8.2 - Decision gate: adopt or drop DFA backend
**Date:** 2026-01-11
**Status:** DEFER (do not adopt at this time)

## Summary

After reviewing the feasibility report (ksk.8.1) and benchmark results, the decision is to **defer adoption of regex-automata** as a runtime dependency. The current dual-engine approach (regex + fancy-regex) is adequate and performs well within all budgets.

## Decision Rationale

### Performance Analysis

| Metric | Current (regex) | regex-automata | Verdict |
|--------|-----------------|----------------|---------|
| Match latency | ~47-49ns | ~48-52ns | No win (2-6% slower) |
| Pack evaluation | ~75-312ns | ~78-318ns | No win (2-4% slower) |
| ReDoS patterns | ~15-22ns | ~15-16ns | Slight win (irrelevant*) |
| Compilation | ~4-5µs | ~6-7µs | Worse (40-60% slower) |

*Both engines already provide O(n) guarantees, so the ReDoS improvement is marginal.

### Maintenance Cost

| Factor | Impact | Assessment |
|--------|--------|------------|
| Third regex engine | High | Adds complexity to CompiledRegex enum |
| Feature flag management | Medium | Optional dependency adds build matrix complexity |
| Pattern classification | Medium | Must decide which patterns use which engine |
| Documentation burden | Low | More engine options to explain |

### Binary Size Impact

- Current binary: 39 MB (release, LTO, stripped)
- Estimated increase: +200-400KB (+2-5%)
- Conflicts with `opt-level = "z"` philosophy

### Current State Assessment

The existing implementation:
- Meets all performance budgets (see src/perf.rs)
- Handles 99%+ of commands via quick-reject before regex
- Uses lazy compilation to amortize pattern compile costs
- Already provides O(n) ReDoS resistance

## Recommendation

**Do not adopt regex-automata at this time.**

The cost-benefit analysis shows:
- **Costs:** 2-6% slower matching, 40-60% slower compilation, 2-5% binary size increase, increased maintenance burden
- **Benefits:** Marginally better ReDoS resistance (not needed), unified API (not compelling)

## Future Reconsideration Triggers

Revisit this decision if:
1. **Performance regression:** If pack evaluation exceeds budget (currently ~100µs target)
2. **Multi-pattern optimization:** If RegexSet approach in ksk.8 Option C shows significant wins
3. **Dependency consolidation:** If fancy-regex is deprecated or unmaintained
4. **Binary size becomes less critical:** If distribution constraints relax

## Actions

1. Keep `regex-automata` as dev-dependency only (for benchmarks)
2. Close ksk.8.2 with this decision documented
3. Consider closing ksk.8 parent task as "deferred"
4. Archive benchmark code in `benches/regex_automata_comparison.rs` for future reference

---

## Appendix: Benchmark Reproduction

```bash
# Run the comparison benchmarks
cargo bench --bench regex_automata_comparison

# Verify current performance meets budgets
cargo bench --bench heredoc_perf
./scripts/e2e_test.sh
```
