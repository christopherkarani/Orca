# Edge Hardware Bench

Hardware bench mode is not flight mode.
It is a bounded `hardware_bench_no_actuation` environment for no-actuation preparation and customer evaluation evidence.

Use:

```bash
edge bench doctor
edge bench check --policy examples/edge/safety/policies/safety-strict.yaml
edge bench report --policy examples/edge/safety/policies/safety-strict.yaml --scenario examples/edge/safety/scenarios/geofence-deny.yaml
```

This document intentionally does not provide flight instructions, real aircraft operation steps, motor/propeller actuation procedures, autonomous flight procedures, or customer hardware procedures.
Bench readiness is not real-flight readiness and is not regulatory certification.
