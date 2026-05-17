# Edge Customer Proof

This folder explains what Edge can demonstrate today for drone and autonomy companies without overclaiming. The scope is simulation/SITL/bench-preparation/customer-evaluation only.

## Architecture Diagrams

Fake adapter:

```text
Agent -> Edge -> Fake Adapter
```

MAVLink gateway:

```text
Agent / Companion Planner -> Edge MAVLink Gateway -> Autopilot/SITL
```

Evaluation:

```text
Command Request -> Policy -> Safety Evaluator -> Approval/Emergency/Data Guard/Health -> Decision -> Audit/Replay
```

Evidence:

```text
Scenario -> Events -> Findings -> Replay -> Safety Report -> Evidence Bundle
```

Edge does not replace the autopilot.

## Start Here

- [What Edge proves](what-edge-proves.md)
- [What Edge does not prove](what-edge-does-not-prove.md)
- [Demo script](demo-script.md)
- [Evidence package](evidence-package.md)
- [Buyer FAQ](buyer-faq.md)
- [Technical FAQ](technical-faq.md)
- [Technical brief](edge-technical-brief.md)
- [Demo recording script](demo-recording-script.md)
- [Red-team summary](redteam-summary.md)
