# Zig coverage slice backlog

**owner:** christopherkarani  
**plan:** `planning/100-percent-test-coverage-agent-plan.md` §6.3 / §10.0  
**rule:** Z1+ agents take **one** `id` per PR. Do not whole-directory DoD.

| id | priority | module | slice_name | residual_behaviors_summary | status |
|----|----------|--------|------------|----------------------------|--------|
| hook-residual-fail-closed | P0 | hook | residual fail-closed + host wire | Close checklist `todo` rows: opencode/openclaw/hermes/claude shell daemon-down host wire; keep all existing fail-closed greens | **open** (Z1 first) |
| intercept-fail-closed-approval | P0 | intercept | fail_closed vs parent approval | Confirm shim/agent_hook fail_closed not overridden; add residual if grep finds gaps | open |
| mcp-proxy-fail-closed | P0 | mcp | proxy residual | Checklist residual upstream death / remaining fail-closed | open |
| sandbox-fail-closed | P0 | sandbox | apply/scrub residual | Multi-OS residual if any checklist todo; e2e already mapped | open |
| policy-load-validate | P0 | policy | load/validate/evaluate edges | Slice from policy residual after inventory; not whole `policy/*` | open |
| policy-effects-decide | P0 | policy | effects deny paths via hook | effects.deny rows already partially tested; residual inventory | open |
| audit-redaction | P1 | audit | redaction + hash chain integrity | Expand audit checklist todos; zh2 tests exist | open |
| hook-host-wire-matrix | P1 | hook | remaining host×event wire contracts | After fail-closed residual; deny/allow wire per Host | open |
| cli-daemon-doctor-fail-closed | P1 | cli | daemon.zig / doctor operational | Operational fail-closed when daemon down | open |

## Caps (binding)

- One behavior family per PR  
- ≤15 test files touched or ≤800 net test LOC unless human override  
- ≤80 LOC production refactor unless human override  
- `./scripts/zig build test` green required (not test-fast alone)  

## How to add a slice

1. Open a short human or agent PR that only appends a row here (or include row add in the work PR with human review).  
2. Link checklist `[[row]]` entries via `slice = "<id>"`.  
3. Do not start work on a slice marked `done` or already owned by another open PR.
