# Aegis Edge Customer Proof

This folder explains what Aegis Edge can demonstrate today for drone and autonomy companies without overclaiming. The scope is simulation/SITL/bench-preparation/customer-evaluation only.

## Architecture Diagrams

Fake adapter:

```text
Agent -> Aegis Edge -> Fake Adapter
```

MAVLink gateway:

```text
Agent / Companion Planner -> Aegis Edge MAVLink Gateway -> Autopilot/SITL
```

Evaluation:

```text
Command Request -> Policy -> Safety Evaluator -> Approval/Emergency/Data Guard/Health -> Decision -> Audit/Replay
```

Evidence:

```text
Scenario -> Events -> Findings -> Replay -> Safety Report -> Evidence Bundle
```

Aegis Edge does not replace the autopilot.

## Start Here

- [What Aegis Edge proves](what-aegis-edge-proves.md)
- [What Aegis Edge does not prove](what-aegis-edge-does-not-prove.md)
- [Demo script](demo-script.md)
- [Evidence package](evidence-package.md)
- [Buyer FAQ](buyer-faq.md)
- [Technical FAQ](technical-faq.md)
- [Technical brief](aegis-edge-technical-brief.md)
- [Demo recording script](demo-recording-script.md)
- [Red-team summary](redteam-summary.md)
