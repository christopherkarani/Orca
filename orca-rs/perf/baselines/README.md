# Performance Baselines

This directory stores JSON artifacts produced by `scripts/perf_baseline.py`.

## Key Improvements

### Lazy Pack Registry + Lazy Regex Compilation (2026-01-11)

Before lazy compilation (175ms p50) vs After (3.1ms p50) = **56x improvement**

| Case | Before p50 | After p50 | Improvement |
|------|------------|-----------|-------------|
| quick_reject (ls -la) | ~175ms | 3.1ms | 56x |
| safe_keyword (git status) | ~175ms | 16ms | 11x |
| destructive_keyword | ~175ms | 16.7ms | 10x |
| bypass | 1.55ms | 1.8ms | same |

Max RSS reduced from ~15MB to ~5-7MB for common cases.

## Guidelines

- Use stable filenames (date or tag) so diffs are easy to review.
- Do not overwrite existing baselines; add new files when re-measuring.
- Record the command line and environment in the baseline JSON itself.

## Example

```
./scripts/perf_baseline.py --bin ./target/release/orca --output perf/baselines/2026-01-10.json
```
