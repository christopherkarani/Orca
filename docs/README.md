# Aegis Documentation

Current docs:

- `quickstart.md`: build, initialize, validate, run, and red-team smoke commands.
- `presets.md`: supported policy presets and assumptions.
- `agent-recipes.md`: local agent, MCP, CI, strict, trusted, red-team, and staged-write recipes.
- `ci.md` and `ci/github-actions.md`: local CI integration examples.
- `release/checklist.md`: Phase 19 release artifact, checksum, signing, SBOM, and install checklist.
- `dev/`: architecture contracts, security invariants, production gates, and phase handoffs.

Aegis reports platform capability limits through `aegis doctor`; docs should not claim transparent sandboxing where the backend reports wrapper-only, observe-only, limited, or unavailable.
