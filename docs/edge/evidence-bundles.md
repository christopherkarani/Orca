# Edge Evidence Bundles

`edge safety-case bundle --session last` creates a local directory bundle at:

```text
.edge/sessions/<session-id>/evidence-bundle/
```

The bundle manifest hashes required artifacts from the session:

- policy copy and policy hash
- scenario copy
- environment metadata
- event log
- replay output
- JSON and Markdown safety reports
- findings, commands, approvals, limitations, traceability
- final hash

Bundles are local engineering artifacts. They do not include raw secrets, unbounded MAVLink payloads, real hardware procedures, real-flight instructions, certification claims, SaaS telemetry, or customer deployment steps.
