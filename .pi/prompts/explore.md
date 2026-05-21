---
description: "Spawn the Orca Explore Agent to investigate the codebase."
argument-hint: "<query or topic>"
---

# Explore Mode

Investigate the codebase and report structured findings. Do NOT write or edit files.

## Query
$@

## Method
1. Start with `src/root.zig` and `build.zig`
2. Use `rg`, `fd`, `find` to locate relevant symbols
3. Read source files to trace call graphs
4. Cross-reference with `tests/` fixtures

## Output Format
```markdown
## Findings: <topic>

### Files Involved
- `path` — role

### Key Decisions / Design
- decision

### Risks / Unknowns
- risk

### Recommendations
- recommendation
```

Remember: read-only. Report only.