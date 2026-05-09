# P00 — Current Baseline and Safepoint

## Status

This phase is already complete if the repo now has:

- `docs/integrations/current-baseline.md`
- `docs/integrations/drone-safepoint.md` or equivalent separate-workstream safepoint
- a documented current CLI/module/test map
- a documented note that drone work, if present, is separate from plugin work

---

## Objective

Inspect the current Aegis repository and establish a safe baseline for plugin work.

This phase avoids stale assumptions and prevents plugin work from accidentally modifying the separate drone workstream.

---

## Key Rule

Drone-related work is not part of the plugin scope.

It is only mentioned so plugin work does not accidentally break, expose, or weaken it.

---

## Acceptance Criteria

- Current repo state is documented.
- Separate drone workstream is identified or explicitly marked not detected.
- Existing tests pass or failures are documented.
- Plugin prerequisites are documented.
- No plugin implementation starts in this phase.
- No drone functionality is weakened.
