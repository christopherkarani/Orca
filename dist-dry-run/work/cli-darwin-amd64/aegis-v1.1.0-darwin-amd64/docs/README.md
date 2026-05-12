# Aegis Documentation

Product package docs:

- `../packages/core/README.md`: Aegis Core shared policy, decision, audit, replay, redaction, fixture, schema registry, experimental ABI skeleton, and capability contract.
- `../packages/cli/README.md`: Aegis CLI desktop and CI AI-agent runtime firewall contract.
- `../packages/edge/README.md`: Aegis Edge domain, policy, MAVLink, and PX4 SITL simulation contract. Aegis Edge is not a flight controller, not an autopilot replacement, not detect-and-avoid, not regulatory approval or certification, and must not be used for real flight.
- `edge/`: Edge domain model, coordinate frames, safety policy, and safety schema notes.

Launch docs:

- `install.md`: source builds, scripts, artifacts, checksums, and package templates.
- `quickstart.md`: first policy, doctor, run, replay, and red-team commands.
- `threat-model.md`: assets, actors, trust boundaries, non-goals, and limitations.
- `policy.md`: schema, modes, priorities, examples, and CI behavior.
- `mcp.md`: stdio MCP inspect/proxy, manifests, mediated methods, and limits.
- `redteam.md`: fixture categories, CI mode, JSON output, and adding fixtures.
- `agent-recipes.md`: generic local recipes and preset notes.
- `ci.md`: GitHub Actions and artifact guidance.
- `replay.md`: audit artifacts, hash-chain verification, and redaction behavior.
- `filesystem-staging.md`, `network.md`, and `commands.md`: enforcement surfaces and limitations.
- `compatibility.md`: consolidated platform matrix.
- `platform-linux.md`, `platform-macos.md`, and `platform-windows.md`: platform-specific capability notes.
- `troubleshooting.md`, `contributing-fixtures.md`, and `release.md`: operations and release references.

Developer docs:

- `presets.md`: supported policy presets and assumptions.
- `release/checklist.md`: Phase 19 release artifact, checksum, signing, SBOM, and install checklist.
- `dev/`: architecture contracts, security invariants, production gates, and phase handoffs.

Aegis reports platform capability limits through `aegis doctor`; docs should not claim transparent sandboxing where the backend reports wrapper-only, observe-only, limited, or unavailable.
