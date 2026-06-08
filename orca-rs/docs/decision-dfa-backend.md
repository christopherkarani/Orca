# Decision: regex-automata DFA Backend

**Decision ID:** ksk.8.2
**Date:** 2026-01-11
**Status:** CLOSED - DROP
**Author:** Claude Opus 4.5

## Context

Task ksk.8 explored using `regex-automata` as an alternative/supplement to the current `regex`/`fancy-regex` dual-engine approach. The feasibility study (ksk.8.1) completed benchmarks and recommended a "hybrid approach" (Option B).

## Decision

**DROP the regex-automata DFA backend initiative.**

The marginal benefits do not justify the added complexity.

## Rationale

### Performance Analysis

| Metric | Current | With regex-automata | Delta |
|--------|---------|---------------------|-------|
| Match time (is_match) | ~47ns | ~48ns | -2% slower |
| Match time (find) | ~49ns | ~52ns | -6% slower |
| Pack evaluation (match found) | ~75ns | ~78ns | -4% slower |
| Pack evaluation (no match) | ~312ns | ~318ns | -2% slower |
| Compilation time | baseline | +40-60% | slower |
| Binary size | 39 MB | +2-5% | larger |

**Key finding:** regex-automata is actually **slower** across all measured operations, not faster. The only improvement is ~27-32% faster handling of pathological ReDoS patterns, which both engines already handle in O(n) time.

### Cost-Benefit Summary

**Costs:**
- Three regex engines to maintain (regex, fancy-regex, regex-automata)
- ~2-5% binary size increase
- Increased code complexity in `CompiledRegex` enum
- Risk of subtle behavioral differences between engines
- Developer cognitive load (which engine for which pattern?)

**Benefits:**
- Slightly better ReDoS resistance on edge cases (already O(n) with current impl)
- Future potential for multi-pattern DFA optimization (speculative)
- Unified API potential (not realized in hybrid approach)

### Decisive Factor

The current implementation already achieves **sub-50ns matching** and **~650 MiB/s throughput**. These numbers are excellent for orca's use case. Adding complexity to achieve marginal (or negative) performance changes is not justified.

## Alternatives Considered

1. **Option A (Full replacement):** Not viable - loses RegexSet benefits, higher compilation time
2. **Option B (Hybrid approach):** Rejected - complexity cost outweighs marginal benefits
3. **Option C (RegexSet optimization):** Could be explored independently without regex-automata

## Action Items

1. Keep `regex-automata` as dev-dependency only (for benchmark comparisons)
2. Close ksk.8 and ksk.8.2 as "dropped/deferred"
3. Remove from active roadmap
4. Revisit if:
   - Performance regression is detected in future
   - regex-automata gains significant advantages in new versions
   - Multi-pattern matching becomes a bottleneck

## References

- [Feasibility Report](regex-automata-feasibility-report.md)
- Benchmark code: `benches/regex_automata_comparison.rs`
- Task tracker: ksk.8, ksk.8.1, ksk.8.2
