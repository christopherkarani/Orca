# Edge Data Guard

Phase 35 adds the Aegis Edge data guard for deterministic fake-adapter, PX4 SITL, ArduPilot SITL, bench-preparation, and customer-evaluation workflows. It classifies telemetry payloads, classifies endpoints, evaluates egress policy, redacts sensitive values before persistence, and emits audit evidence. It does not send network traffic.

Aegis Edge remains simulation/SITL/customer-evaluation software. It is not real-flight readiness, certification, detect-and-avoid, or autopilot replacement evidence.

The reusable module lives under `packages/edge/src/data_guard/` and is used by the MAVLink gateway, PX4/ArduPilot adapter path through the gateway, safety-case evidence, CLI commands, and data guard red-team fixtures.

Local examples live under `examples/edge/data-guard/`:

- `policies/`: strict, observe, ground-control, and safety-report policies.
- `payloads/`: synthetic vehicle state, exact geolocation, mission plan, video metadata, fake secret, and safety report payloads.
- `endpoints/`: local ground-control, fake/SITL, simulated customer, direct IP, webhook, paste, tunnel, and long-query endpoints.
- `scenarios/`: deterministic allow/deny/observe checks with no external network dependency.

Useful commands:

```sh
aegis-edge data doctor
aegis-edge data classify --payload examples/edge/data-guard/payloads/mission-plan.json
aegis-edge data evaluate --policy examples/edge/data-guard/policies/data-guard-strict.yaml --payload examples/edge/data-guard/payloads/mission-plan.json --endpoint examples/edge/data-guard/endpoints/webhook-site.json
aegis-edge data redact --payload examples/edge/data-guard/payloads/fake-secret-payload.json
aegis-edge data scenario run --policy examples/edge/data-guard/policies/data-guard-strict.yaml --scenario examples/edge/data-guard/scenarios/mission-plan-to-webhook-deny.yaml
aegis-edge network explain --policy examples/edge/data-guard/policies/data-guard-strict.yaml --endpoint examples/edge/data-guard/endpoints/unknown-direct-ip.json
```

CI/noninteractive mode never prompts. Ask decisions become deny when prompting is unavailable. Deny beats allow, and explicit endpoint allow still has to pass telemetry-channel and data-class policy.
