# Domain test slices

Focused Zig unit gates for coding agents (avoid full monopath `test-lib` when possible).

| Slice | Build step | Root / mapping | Script |
|-------|------------|----------------|--------|
| sandbox | `test-sandbox` | `src/sandbox_slice_root.zig` | `./scripts/test-slice.sh sandbox` |
| intercept | `test-intercept` | `src/intercept_slice_root.zig` | `./scripts/test-slice.sh intercept` |
| policy | `test-policy` | maps to `test-core` + `test-core-contract` | `./scripts/test-slice.sh policy` |
| lib | `test-lib` | full monopath (`src/root.zig`) | `./scripts/test-slice.sh lib` |

Filter by name substring (Zig 0.16 **compile-time** `-Dtest-filter`; not runtime `-- --test-filter`):

```bash
./scripts/test-slice.sh sandbox --filter Seatbelt
./scripts/zig build test-lib -Dtest-filter=Spinner
```

**Note:** A true `src/policy/*`-only root is blocked by Zig 0.16 API drift in deep core/policy unit helpers when compiled outside the monopath. Use `test-policy` for the stable package boundary; use monopath L1 when you need the full product graph.

See `Agents.md` → Verification gates.
