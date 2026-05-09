# Separate Workstream Guardrails

## Purpose

The Aegis repository may contain other workstreams, including drone-related work.

The plugin plan must not break, expose, or expand those workstreams.

---

## Rules

Plugin work must not:

- modify safety-sensitive modules unless required to preserve build/test compatibility
- expose unrelated commands through plugins
- add plugin skills for unrelated workstreams
- add demos for unrelated safety-sensitive workstreams
- add operational instructions for safety-sensitive systems
- weaken tests
- weaken policies
- auto-approve high-risk operations

---

## Drone-specific Note

If drone work exists in the repo, it is out of scope for the plugin plan.

Plugin docs may say:

```text
A separate drone workstream exists in this repository. The Aegis plugins do not expose or modify drone functionality.
```

Plugin docs should not include drone-control procedures or demos.
