# Rule-Level Metrics: Struct Mapping & Reuse Strategy

> Design document for `git_safety_guard-1dri.1`
>
> This document inventories existing history analytics structs and maps rule-level
> metrics needs to them, ensuring no duplicate or competing analytics pipelines.

---

## Executive Summary

**Finding:** The existing history analytics structs in `src/history/schema.rs` are
well-designed and sufficient for rule-level metrics. No new analytics structs are
needed. The `PatternEffectiveness` struct already captures per-rule metrics, and
the `rule_id` field in `CommandEntry` provides stable rule identifiers.

**Recommendation:** Reuse existing structs. Extend query/aggregation logic only.

---

## Struct Inventory

### Core Data Types

| Struct | Location | Purpose | Rule-Metrics Relevance |
|--------|----------|---------|------------------------|
| `CommandEntry` | L133 | Single command record | **Primary data source** - contains `rule_id`, `pack_id`, `pattern_name`, `outcome` |
| `Outcome` | L81 | Enum: Allow/Deny/Warn/Bypass | Categorizes command outcomes for metrics |

### Statistics Types

| Struct | Location | Purpose | Rule-Metrics Relevance |
|--------|----------|---------|------------------------|
| `OutcomeStats` | L230 | Aggregate counts (allowed/denied/warned/bypassed) | Can aggregate by rule |
| `PerformanceStats` | L239 | Latency percentiles (p50/p95/p99/max) | Could extend for per-rule latency |
| `PatternStat` | L248 | Pattern name + count + pack_id | **Direct reuse** for top patterns |
| `HistoryStats` | L325 | Complete stats for time window | Contains `top_patterns: Vec<PatternStat>` |
| `StatsTrends` | L271 | Period-over-period comparison | Extendable for rule trends |

### Analytics Types (Key for Rule-Metrics)

| Struct | Location | Purpose | Rule-Metrics Relevance |
|--------|----------|---------|------------------------|
| `PatternEffectiveness` | L2177 | Per-pattern metrics with bypass analysis | **PERFECT FIT** - use directly |
| `PotentialGap` | L2195 | Dangerous commands that were allowed | Coverage gap analysis |
| `RecommendationType` | L2208 | Enum: RelaxPattern/EnablePack/etc. | Tuning recommendations |
| `PackRecommendation` | L2225 | Actionable recommendation with config | Extend for rule-specific recs |
| `PackEffectivenessAnalysis` | L2246 | Complete analysis result | Already groups by pattern |

---

## Rule Identifier Design

The `rule_id` is already defined in `CommandEntry`:

```rust
/// Stable rule identifier: `pack_id:pattern_name`
/// Present only for denied commands that matched a pattern.
/// Format: "core.git:reset-hard", "core.filesystem:rm-rf-root"
pub rule_id: Option<String>,
```

**Key methods in `CommandEntry`:**
- `compute_rule_id()` → Constructs `pack_id:pattern_name`
- `get_rule_id()` → Returns stored or computed value
- `ensure_rule_id()` → Sets `rule_id` if computable

This provides stable, human-readable identifiers for:
- Allowlisting specific rules
- Aggregating metrics per rule
- Tracking rule effectiveness over time

---

## PatternEffectiveness: The Core Struct

This struct is the foundation for rule-level metrics:

```rust
pub struct PatternEffectiveness {
    /// Pattern name (e.g., "reset-hard")
    pub pattern: String,
    /// Pack ID the pattern belongs to (e.g., "core.git")
    pub pack_id: Option<String>,
    /// Total times this pattern triggered (deny + bypass)
    pub total_triggers: u64,
    /// Times the pattern blocked a command (deny)
    pub denied_count: u64,
    /// Times the pattern was bypassed (allow-once)
    pub bypassed_count: u64,
    /// Bypass rate as a percentage (0.0-100.0)
    pub bypass_rate: f64,
}
```

**Mapping to rule_id:** `rule_id = {pack_id}:{pattern}`

**Already computed in `PackEffectivenessAnalysis`:**
- `high_value_patterns: Vec<PatternEffectiveness>` - High volume, low bypass
- `potentially_aggressive: Vec<PatternEffectiveness>` - High bypass rate

---

## Reuse vs Extend Analysis

### Direct Reuse (No Changes)

| Struct | Usage |
|--------|-------|
| `CommandEntry` | Query by `rule_id` for per-rule history |
| `PatternEffectiveness` | Per-rule metrics with bypass analysis |
| `PatternStat` | Simple name+count for top rules |
| `OutcomeStats` | Aggregate outcomes per rule |

### Extend (Add Fields/Methods)

| Struct | Extension | Reason |
|--------|-----------|--------|
| `PatternEffectiveness` | Add `first_seen_ts`, `last_seen_ts` | Track rule activity timeline |
| `PatternEffectiveness` | Add `projects: Vec<String>` | See which projects trigger rule |
| `PackEffectivenessAnalysis` | Add `per_rule_metrics: HashMap<String, PatternEffectiveness>` | Direct rule_id lookup |

### Do NOT Create

To avoid competing pipelines, these should **NOT** be created:

- ~~`RuleMetrics`~~ → Use `PatternEffectiveness`
- ~~`RuleEffectiveness`~~ → Use `PatternEffectiveness`
- ~~`RuleStats`~~ → Use `PatternStat` with pack_id
- ~~`RuleAnalysis`~~ → Use `PackEffectivenessAnalysis`

---

## Query Patterns for Rule-Level Metrics

### Per-Rule Trigger Count

```sql
SELECT rule_id, COUNT(*) as triggers
FROM commands
WHERE rule_id IS NOT NULL
GROUP BY rule_id
ORDER BY triggers DESC;
```

### Per-Rule Bypass Rate

```sql
SELECT rule_id,
       COUNT(*) as total,
       SUM(CASE WHEN outcome = 'deny' THEN 1 ELSE 0 END) as denied,
       SUM(CASE WHEN outcome = 'bypass' THEN 1 ELSE 0 END) as bypassed,
       (bypassed * 100.0 / total) as bypass_rate
FROM commands
WHERE rule_id IS NOT NULL
GROUP BY rule_id;
```

### Rule Activity Over Time

```sql
SELECT rule_id,
       date(timestamp) as day,
       COUNT(*) as triggers
FROM commands
WHERE rule_id IS NOT NULL
GROUP BY rule_id, day
ORDER BY rule_id, day;
```

---

## Implementation Guidance

### For `orca history stats --rule <rule_id>`

1. Query `commands` table filtered by `rule_id`
2. Compute `OutcomeStats` from results
3. Return `PatternEffectiveness` struct populated from query
4. No new structs needed

### For `orca history analyze`

The existing `PackEffectivenessAnalysis` already computes `PatternEffectiveness`
for each pattern. To add rule-level access:

1. Add `rule_id` to `PatternEffectiveness` (computed from pack_id + pattern)
2. Add `by_rule_id: HashMap<String, PatternEffectiveness>` to analysis result
3. No new analysis pipeline needed

### For Rule-Specific Recommendations

Extend `PackRecommendation` with:

```rust
/// Rule ID this recommendation targets (if rule-specific)
#[serde(skip_serializing_if = "Option::is_none")]
pub rule_id: Option<String>,
```

---

## Acceptance Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Rule-metrics design references existing structs | ✅ | Uses `PatternEffectiveness`, `PatternStat`, `CommandEntry` |
| No duplicate analytics pipelines | ✅ | No new `Rule*` structs proposed |
| Clear mapping documented | ✅ | This document |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-16 | Initial design document |

---

## Related Issues

- **Parent:** `git_safety_guard-1dri` (Rule-Level Metrics: Track per-rule stats)
- **Blocked by:** None
- **Blocks:** `git_safety_guard-1dri.2` (orca history stats --rule)
